# main.rb
require 'dotenv'
require 'google_drive'
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative 'mastodon_client'
require_relative 'command_parser'

puts "[시작] 호그와트 교수봇 기동 완료"
puts "   BASE_URL: #{ENV['MASTODON_BASE_URL']}"
puts "   TOKEN: #{ENV['MASTODON_TOKEN'][0..10]}..." if ENV['MASTODON_TOKEN']

# 시트 설정
google_credentials = ENV['GOOGLE_CREDENTIALS_PATH']
google_sheet_id = ENV['GOOGLE_SHEET_ID']

if google_credentials && google_sheet_id
  puts "[시트] 인증 파일: #{google_credentials}"
  if File.exist?(google_credentials)
    puts "        인증 파일 확인됨"
  else
    puts "        인증 파일 없음! 다운로드 필요"
  end
  puts "        시트 ID: #{google_sheet_id[0..10]}..."
else
  puts "[오류] .env에서 GOOGLE_CREDENTIALS_PATH 또는 GOOGLE_SHEET_ID 설정 누락"
end

# 마스토돈 연결 확인
unless MastodonClient.test_connection
  puts "[오류] 마스토돈 연결 실패! 설정을 확인하세요"
  exit 1
end

# 구글 시트 연결 확인
begin
  session = GoogleDrive::Session.from_service_account_key(google_credentials)
  spreadsheet = session.spreadsheet_by_key(google_sheet_id)
  puts "[시트] 구글 시트 연결 성공: #{spreadsheet.title}"

  required_sheets = ['사용자', '응답', '기숙사점수']
  existing = spreadsheet.worksheets.map(&:title)
  missing = required_sheets - existing

  if missing.empty?
    puts "        필수 워크시트 모두 존재"
  else
    puts "        누락된 워크시트: #{missing.join(', ')}"
  end
rescue => e
  puts "[오류] 구글 시트 연결 실패: #{e.message}"
  puts "       기능이 일부 제한될 수 있습니다"
end

puts "\n[봇 준비] 교수봇이 멘션을 대기 중입니다"
puts "          명령어 예시: [입학/해리포터], [출석], [과제]"
puts "          종료하려면 Ctrl+C를 누르세요"

# 자동 툿 발송 상태 저장
$last_auto_posts = {}

# 자동 툿 발송 스케줄러
Thread.new do
  loop do
    now = Time.now.getlocal("+09:00")
    time_str = now.strftime("%H:%M")
    date_str = now.strftime("%Y-%m-%d")
    key = "#{date_str}-#{time_str}"

    unless $last_auto_posts[key]
      case time_str
      when "09:00"
        if CommandParser.should_fire_auto_post?("9:00")
          MastodonClient.post_status(CommandParser.generate_daily_attendance_notice)
          $last_auto_posts[key] = true
        end
      when "22:00"
        if CommandParser.should_fire_auto_post?("22:00")
          MastodonClient.post_status(CommandParser.generate_attendance_close_notice)
          $last_auto_posts[key] = true
        end
      when "02:00"
        if CommandParser.should_fire_auto_post?("2:00")
          MastodonClient.post_status(CommandParser.generate_night_lockdown_notice)
          $last_auto_posts[key] = true
        end
      when "06:00"
        if CommandParser.should_fire_auto_post?("6:00")
          MastodonClient.post_status(CommandParser.generate_morning_unlock_notice)
          $last_auto_posts[key] = true
        end
      end
    end

    sleep 60
  end
end

# 멘션 수신 대기
start_time = Time.now
mention_count = 0
error_count = 0

loop do
  begin
    MastodonClient.listen_mentions do |mention|
      begin
        mention_count += 1
        puts "[멘션] ##{mention_count} 처리 중..."
        CommandParser.handle(mention)
      rescue => e
        error_count += 1
        puts "[에러] 멘션 처리 실패: #{e.message}"
        puts "       사용자: @#{mention.account.acct rescue 'unknown'}"
        puts "       내용: #{mention.status.content.gsub(/<[^>]*>/, '').strip rescue 'unknown'}"
        puts "       위치: #{e.backtrace.first(3).join("\n         ")}"
        begin
          MastodonClient.reply(mention, "죄송합니다. 오류가 발생했습니다. 잠시 후 다시 시도해주세요.")
        rescue
          puts "[오류] 응답 전송도 실패"
        end
      end
    end
  rescue Interrupt
    puts "\n[종료] 교수봇을 종료합니다"
    uptime = Time.now - start_time
    puts "        운영 시간: #{(uptime / 3600).to_i}시간 #{((uptime % 3600) / 60).to_i}분"
    puts "        총 멘션 처리: #{mention_count}건"
    puts "        오류: #{error_count}건"
    puts "        성공률: #{mention_count > 0 ? ((mention_count - error_count) * 100 / mention_count).round(1) : 0}%"
    break
  rescue => e
    error_count += 1
    puts "[에러] 연결 실패: #{e.message} (#{e.class})"
    puts "       재시도까지 15초 대기"
    sleep 15
  end

  sleep 15
end
