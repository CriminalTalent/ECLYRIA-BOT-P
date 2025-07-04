require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__))
require_relative 'mastodon_client'
require_relative 'command_parser'
require 'rufus-scheduler'
require 'tzinfo'

puts "🎓 호그와트 교수봇 기동 완료!"
puts "📡 BASE_URL: #{ENV['MASTODON_BASE_URL']}"
puts "🔐 TOKEN 시작: #{ENV['MASTODON_TOKEN'][0..10]}..." if ENV['MASTODON_TOKEN']

# 한국 시간대 설정
TZ = TZInfo::Timezone.get('Asia/Seoul')

# 구글 시트 설정 확인
puts "\n📊 구글 시트 설정 확인 중..."
google_credentials = ENV['GOOGLE_CREDENTIALS_PATH']
google_sheet_id = ENV['GOOGLE_SHEET_ID']

if google_credentials && google_sheet_id && File.exist?(google_credentials)
  puts "   ✅ 구글 시트 설정 완료"
  puts "   📄 시트 ID: #{google_sheet_id[0..10]}..."
else
  puts "   ❌ 구글 시트 설정 필요 (.env 파일 확인)"
end

# 마스토돈 연결 테스트
puts "\n🔌 마스토돈 연결 테스트 중..."
unless MastodonClient.test_connection
  puts "❌ 마스토돈 연결 실패! .env 파일의 설정을 확인하세요"
  exit 1
end

# 스케줄러 초기화
scheduler = Rufus::Scheduler.new

puts "\n⏰ 자동 출석 스케줄러 설정 중..."

# 매일 오전 9시에 출석 툿 자동 게시
scheduler.cron '0 9 * * *', :timezone => 'Asia/Seoul' do
  puts "\n🕘 오전 9시! 출석체크 시작!"
  
  begin
    attendance_message = CommandParser.get_daily_attendance_message
    if attendance_message
      response = MastodonClient.post_status(attendance_message)
      if response
        puts "✅ 출석 툿 게시 완료!"
        puts "   📝 내용: #{attendance_message[0..50]}..."
      else
        puts "❌ 출석 툿 게시 실패"
      end
    else
      puts "⚠️  출석 메시지를 가져올 수 없습니다"
    end
  rescue => e
    puts "❌ 자동 출석 툿 오류: #{e.message}"
  end
end

# 매일 오후 10시에 출석 마감 알림
scheduler.cron '0 22 * * *', :timezone => 'Asia/Seoul' do
  puts "\n🕐 오후 10시! 출석체크 마감!"
  
  begin
    closing_message = "📚 오늘의 출석체크가 마감되었습니다.\n내일 아침 9시에 다시 만나요! 🌙✨"
    response = MastodonClient.post_status(closing_message)
    if response
      puts "✅ 출석 마감 알림 완료!"
    end
  rescue => e
    puts "❌ 출석 마감 알림 오류: #{e.message}"
  end
end

puts "   ✅ 자동 스케줄 등록 완료"
puts "   🕘 매일 09:00 - 출석체크 시작"
puts "   🕐 매일 22:00 - 출석체크 마감"

puts "\n🏫 호그와트 교수 업무 시작!"
puts "🔔 멘션 수신 대기 중..."
puts "   📚 출석체크: [출석]"
puts "   🏆 점수관리: [점수부여/학생명/점수/사유]"
puts "   🏠 기숙사: [기숙사배정/학생명/기숙사명]"
puts "   종료하려면 Ctrl+C를 누르세요"

# 봇 실행 통계
start_time = Time.now
mention_count = 0
attendance_count = 0
error_count = 0

loop do
  begin
    MastodonClient.listen_mentions do |mention|
      begin
        mention_count += 1
        puts "\n📨 멘션 ##{mention_count} 처리 중..."
        
        # 출석체크 멘션인지 확인
        content = mention.status.content.gsub(/<[^>]*>/, '').strip
        if content.include?('[출석]') || content.include?('출석')
          attendance_count += 1
          puts "   📚 출석체크 ##{attendance_count}"
        end
        
        CommandParser.handle(mention)
        
      rescue => e
        error_count += 1
        puts "❌ 멘션 처리 오류 ##{error_count}: #{e.message}"
        puts "   사용자: @#{mention.account.acct rescue 'unknown'}"
        puts "   내용: #{mention.status.content.gsub(/<[^>]*>/, '').strip rescue 'unknown'}"
        puts "   #{e.backtrace.first(3).join("\n   ")}"
        
        # 오류 시 사용자에게 알림
        begin
          MastodonClient.reply(mention, "죄송합니다. 일시적인 교무 시스템 오류가 발생했습니다. 잠시 후 다시 시도해주세요. 📚")
        rescue
          puts "   응답 전송도 실패했습니다"
        end
      end
    end
    
  rescue Interrupt
    puts "\n\n🛑 교수봇 종료 중..."
    uptime = Time.now - start_time
    hours = (uptime / 3600).to_i
    minutes = ((uptime % 3600) / 60).to_i
    
    puts "📊 교무 업무 통계:"
    puts "   ⏱️  근무 시간: #{hours}시간 #{minutes}분"
    puts "   📨 처리한 멘션: #{mention_count}개"
    puts "   📚 출석체크: #{attendance_count}개"
    puts "   ❌ 오류 발생: #{error_count}개"
    puts "   📈 성공률: #{mention_count > 0 ? ((mention_count - error_count) * 100.0 / mention_count).round(1) : 0}%"
    
    puts "🏫 호그와트 교무실 문을 닫습니다. 좋은 하루 되세요!"
    scheduler.shutdown(:wait)
    break
    
  rescue => e
    error_count += 1
    puts "❌ 시스템 오류 ##{error_count}: #{e.message}"
    puts "   #{e.class}: #{e.backtrace.first}"
    puts "🔄 15초 후 재연결 시도..."
    sleep 15
  end
  
  sleep 15
end
