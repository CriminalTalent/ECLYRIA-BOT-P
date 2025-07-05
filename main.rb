# main.rb
require 'dotenv'
require 'set'

# .env 파일 로드 (현재 디렉토리에서)
Dotenv.load('.env')

# 디버깅: 환경변수 확인
puts "DEBUG - 현재 디렉토리: #{Dir.pwd}"
puts "DEBUG - .env 파일 존재: #{File.exist?('.env')}"
puts "DEBUG - MASTODON_BASE_URL: '#{ENV['MASTODON_BASE_URL']}'"
puts "DEBUG - MASTODON_TOKEN: #{ENV['MASTODON_TOKEN'] ? '존재함' : '없음'}"

require_relative 'mastodon_client'
require_relative 'command_parser'

puts "[시작] 호그와트 교수봇 기동 중..."
puts "   BASE_URL: #{ENV['MASTODON_BASE_URL']}"
puts "   TOKEN 시작: #{ENV['MASTODON_TOKEN'][0..10]}..." if ENV['MASTODON_TOKEN']

# 구글 시트 설정 확인
puts "\n[시트] 설정 확인 중..."
google_credentials = ENV['GOOGLE_CREDENTIALS_PATH']
google_sheet_id = ENV['GOOGLE_SHEET_ID']
google_available = false

if google_credentials && google_sheet_id
  puts "   인증 파일: #{google_credentials}"
  if File.exist?(google_credentials)
    puts "   인증 파일 존재 확인"
    google_available = true
  else
    puts "   [경고] 인증 파일 없음: #{google_credentials}"
  end
  puts "   시트 ID: #{google_sheet_id[0..10]}..."
else
  puts "   [경고] .env 파일에 시트 설정이 없습니다"
end

# 마스토돈 연결 테스트
puts "\n[테스트] 마스토돈 연결..."
unless MastodonClient.test_connection
  puts "[실패] 마스토돈 연결 실패"
  exit 1
end

# 구글 시트 연결 테스트 (선택적)
puts "\n[테스트] 구글 시트 연결..."
if google_available
  begin
    require 'google_drive'
    session = GoogleDrive::Session.from_service_account_key(google_credentials)
    spreadsheet = session.spreadsheet_by_key(google_sheet_id)
    puts "   ✅ 시트 제목: #{spreadsheet.title}"
    
    required_sheets = ['사용자', '응답', '기숙사점수']
    missing = required_sheets - spreadsheet.worksheets.map(&:title)
    if missing.empty?
      puts "   ✅ 모든 필수 워크시트 존재 확인"
    else
      puts "   ⚠️ 누락된 워크시트: #{missing.join(', ')}"
    end
  rescue => e
    puts "   ❌ 구글 시트 연결 실패: #{e.message}"
    puts "   📝 마스토돈 기능만 사용합니다"
    google_available = false
  end
else
  puts "   📝 구글 시트 설정 없음 - 마스토돈 기능만 사용"
end

puts "\n[대기] 교수봇 준비 완료. 멘션 수신 대기 중..."
puts "   📚 예시 명령어: [입학/이름], [출석], [과제]"
puts "   🔗 구글 시트 연동: #{google_available ? '활성화' : '비활성화'}"

start_time = Time.now
mention_count = 0
error_count = 0
processed_mentions = Set.new
last_cleanup = Time.now

# 자동 툿 스케줄러 (구글 시트 사용 가능할 때만)
if google_available
  Thread.new do
    loop do
      begin
        now = Time.now.getlocal("+09:00")
        current_time = now.strftime('%H:%M')
        
        case current_time
        when '09:00'
          msg = "🌅 좋은 아침입니다! 오늘의 출석을 시작해주세요. [출석] 명령어로 참여하세요!"
          MastodonClient.post_status(msg)
          puts "[자동툿] 아침 출석 알림 발송"
        when '22:00'
          msg = "🌙 출석 마감이 임박했습니다! 아직 출석하지 않으신 분들은 서둘러주세요."
          MastodonClient.post_status(msg)
          puts "[자동툿] 저녁 출석 마감 알림 발송"
        when '02:00'
          msg = "🕐 새벽 2시입니다. 기숙사 통금 시간이니 푹 쉬시기 바랍니다."
          MastodonClient.post_status(msg)
          puts "[자동툿] 통금 알림 발송"
        when '06:00'
          msg = "🌄 새벽 6시입니다. 통금이 해제되었습니다. 좋은 하루 되세요!"
          MastodonClient.post_status(msg)
          puts "[자동툿] 통금 해제 알림 발송"
        end
      rescue => e
        puts "[오류] 자동 툿 스케줄 오류: #{e.message}"
      end
      sleep 60
    end
  end
end

# 멘션 처리 루프
loop do
  begin
    # 메모리 정리 (1시간마다)
    if Time.now - last_cleanup > 3600
      old_size = processed_mentions.size
      # 1시간 이전 멘션 ID들 제거 (메모리 절약)
      processed_mentions.clear if old_size > 1000
      last_cleanup = Time.now
      puts "[정리] 처리된 멘션 #{old_size}개 정리 완료" if old_size > 100
    end
    
    MastodonClient.listen_mentions do |mention|
      begin
        # 중복 처리 방지
        mention_id = mention.status.id
        if processed_mentions.include?(mention_id)
          puts "[스킵] 이미 처리된 멘션: #{mention_id}"
          next
        end
        
        # 봇 시작 이전 멘션 스킵
        begin
          mention_time = Time.parse(mention.status.created_at)
          if mention_time < start_time
            puts "[스킵] 봇 시작 이전 멘션: #{mention_time.strftime('%H:%M:%S')}"
            processed_mentions.add(mention_id)
            next
          end
        rescue => time_error
          puts "[경고] 멘션 시간 파싱 실패: #{time_error.message}"
        end
        
        # 멘션 처리
        processed_mentions.add(mention_id)
        mention_count += 1
        
        user_acct = mention.account.acct
        user_display = mention.account.display_name || user_acct
        content = mention.status.content.gsub(/<[^>]*>/, '').strip
        
        puts "\n[멘션] ##{mention_count} 📩"
        puts "   👤 사용자: @#{user_acct} (#{user_display})"
        puts "   📝 내용: #{content}"
        puts "   🕐 시간: #{mention.status.created_at rescue '알 수 없음'}"
        puts "   🆔 ID: #{mention_id}"
        
        # 구글 시트 사용 불가능할 때 간단한 응답
        unless google_available
          simple_response = case content.downcase
          when /입학|등록/
            "#{user_display}님, 현재 구글 시트 연동이 비활성화되어 있어 등록 기능을 사용할 수 없습니다. 관리자에게 문의해주세요."
          when /출석/
            "#{user_display}님, 현재 구글 시트 연동이 비활성화되어 있어 출석 체크를 할 수 없습니다."
          when /과제/
            "#{user_display}님, 현재 구글 시트 연동이 비활성화되어 있어 과제 제출을 처리할 수 없습니다."
          else
            "#{user_display}님, 안녕하세요! 현재 시스템 점검 중입니다. 나중에 다시 시도해주세요. 🏰"
          end
          
          MastodonClient.reply(mention, simple_response)
          puts "   ✅ 간단 응답 전송 완료"
          next
        end
        
        # 구글 시트 연동된 처리
        CommandParser.handle(mention)
        puts "   ✅ 멘션 처리 완료"
        
      rescue => e
        error_count += 1
        puts "   ❌ 멘션 처리 실패: #{e.message}"
        puts "   📍 위치: #{e.backtrace.first}"
        
        # 오류 응답
        begin
          error_msg = "#{mention.account.display_name || mention.account.acct}님, 죄송합니다. 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요. 🔧"
          MastodonClient.reply(mention, error_msg)
          puts "   📤 오류 응답 전송 완료"
        rescue => reply_error
          puts "   💥 응답 전송도 실패: #{reply_error.message}"
        end
      end
    end
    
  rescue Interrupt
    puts "\n[종료] 교수봇 종료 요청 수신 (Ctrl+C)"
    break
    
  rescue => e
    error_count += 1
    puts "\n💥 [오류] 메인 루프 예외: #{e.message}"
    puts "📍 위치: #{e.backtrace.first}"
    puts "⏰ 15초 후 재시도..."
    sleep 15
  end
  
  sleep 5
end

# 종료 통계
uptime = Time.now - start_time
h = (uptime / 3600).to_i
m = ((uptime % 3600) / 60).to_i
s = (uptime % 60).to_i

puts "\n" + "="*50
puts "📊 [통계] 호그와트 교수봇 운영 리포트"
puts "="*50
puts "⏰ 총 운영 시간: #{h}시간 #{m}분 #{s}초"
puts "📩 총 멘션 처리: #{mention_count}건"
puts "❌ 오류 발생: #{error_count}건"
puts "💾 처리된 멘션 ID: #{processed_mentions.size}개"
puts "📈 성공률: #{mention_count > 0 ? ((mention_count - error_count) * 100.0 / mention_count).round(1) : 0}%"
puts "🔗 구글 시트 연동: #{google_available ? '활성화됨' : '비활성화됨'}"
puts "="*50
puts "🏰 [완료] 호그와트 교수봇이 안전하게 종료되었습니다."
