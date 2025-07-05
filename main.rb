# main.rb
require 'dotenv'
require 'set'

Dotenv.load(File.expand_path('../.env', __dir__))
require_relative 'mastodon_client'
require_relative 'command_parser'

puts "[시작] 호그와트 교수봇 기동 중..."
puts "   BASE_URL: #{ENV['MASTODON_BASE_URL']}"
puts "   TOKEN 시작: #{ENV['MASTODON_TOKEN'][0..10]}..." if ENV['MASTODON_TOKEN']

# 구글 시트 설정 확인
puts "\n[시트] 설정 확인 중..."
google_credentials = ENV['GOOGLE_CREDENTIALS_PATH']
google_sheet_id = ENV['GOOGLE_SHEET_ID']

if google_credentials && google_sheet_id
  puts "   인증 파일: #{google_credentials}"
  if File.exist?(google_credentials)
    puts "   인증 파일 존재 확인"
  else
    puts "   [경고] 인증 파일 없음: #{google_credentials}"
  end
  puts "   시트 ID: #{google_sheet_id[0..10]}..."
else
  puts "   [경고] .env 파일에 시트 설정이 없습니다 (GOOGLE_CREDENTIALS_PATH / GOOGLE_SHEET_ID)"
end

# 마스토돈 연결 테스트
puts "\n[테스트] 마스토돈 연결..."
unless MastodonClient.test_connection
  puts "[실패] 마스토돈 연결 실패"
  exit 1
end

# 구글 시트 연결 테스트
puts "\n[테스트] 구글 시트 연결..."
begin
  require 'google_drive'
  if File.exist?(google_credentials)
    session = GoogleDrive::Session.from_service_account_key(google_credentials)
    spreadsheet = session.spreadsheet_by_key(google_sheet_id)
    puts "   시트 제목: #{spreadsheet.title}"
    required_sheets = ['사용자', '응답', '기숙사점수']
    missing = required_sheets - spreadsheet.worksheets.map(&:title)
    if missing.empty?
      puts "   모든 필수 워크시트 존재 확인"
    else
      puts "   [주의] 누락된 워크시트: #{missing.join(', ')}"
    end
  else
    puts "[오류] 인증 파일이 존재하지 않습니다: #{google_credentials}"
  end
rescue => e
  puts "[실패] 구글 시트 연결 오류: #{e.message}"
end

puts "\n[대기] 교수봇 준비 완료. 멘션 수신 대기 중..."
puts "   예시 명령어: [입학/이름], [출석], [과제]"

start_time = Time.now
mention_count = 0
error_count = 0
processed_mentions = Set.new

# ✅ 자동 툿 스케줄러
Thread.new do
  loop do
    begin
      now = Time.now.getlocal("+09:00")
      current_time = now.strftime('%H:%M')
      
      case current_time
      when '09:00'
        msg = CommandParser.generate_scheduled_message("아침 출석 자동툿")
        MastodonClient.post_status(msg) if msg
      when '22:00'
        msg = CommandParser.generate_scheduled_message("저녁 출석 마감 자동툿")
        MastodonClient.post_status(msg) if msg
      when '02:00'
        msg = CommandParser.generate_scheduled_message("새벽 통금 알람")
        MastodonClient.post_status(msg) if msg
      when '06:00'
        msg = CommandParser.generate_scheduled_message("통금 해제 알람")
        MastodonClient.post_status(msg) if msg
      end
    rescue => e
      puts "[오류] 스케줄 툿 오류: #{e.message}"
    end
    sleep 60
  end
end

# ✅ 멘션 처리 루프 (중복 처리 방지 추가)
loop do
  begin
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
            puts "[스킵] 봇 시작 이전 멘션: #{mention_time}"
            processed_mentions.add(mention_id)
            next
          end
        rescue => time_error
          puts "[경고] 멘션 시간 파싱 실패: #{time_error.message}"
        end
        
        # 멘션 처리
        processed_mentions.add(mention_id)
        mention_count += 1
        puts "\n[멘션] ##{mention_count} 처리 시작 (ID: #{mention_id})"
        puts "   시간: #{mention.status.created_at rescue '알 수 없음'}"
        puts "   사용자: @#{mention.account.acct}"
        
        CommandParser.handle(mention)
        
      rescue => e
        error_count += 1
        puts "[에러] 멘션 처리 실패: #{e.message}"
        puts "   사용자: @#{mention.account.acct rescue '알 수 없음'}"
        puts "   내용: #{mention.status.content.gsub(/<[^>]*>/, '').strip rescue '없음'}"
        begin
          MastodonClient.reply(mention, "죄송합니다. 시스템 오류가 발생하였습니다. 잠시 후 다시 시도해 주세요.")
        rescue
          puts "   [실패] 응답 전송도 실패"
        end
      end
    end
  rescue Interrupt
    puts "\n[종료] 교수봇 종료 요청 수신"
    uptime = Time.now - start_time
    h = (uptime / 3600).to_i
    m = ((uptime % 3600) / 60).to_i
    puts "\n[통계] 총 운영 시간: #{h}시간 #{m}분"
    puts "   총 멘션 처리: #{mention_count}건"
    puts "   오류 발생: #{error_count}건"
    puts "   처리된 멘션 ID: #{processed_mentions.size}개"
    puts "   성공률: #{mention_count > 0 ? ((mention_count - error_count) * 100.0 / mention_count).round(1) : 0}%"
    puts "[완료] 교수봇 종료"
    break
  rescue => e
    error_count += 1
    puts "[오류] 메인 루프 예외: #{e.message}"
    puts "   15초 후 재시도"
    sleep 15
  end
  sleep 15
end
