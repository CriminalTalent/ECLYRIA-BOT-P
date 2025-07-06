# frozen_string_literal: false
require 'dotenv/load'
require 'mastodon'
require 'google_drive'
require 'json'
require 'set'

puts "DEBUG - 현재 디렉토리: #{Dir.pwd}"
puts "DEBUG - .env 파일 존재: #{File.exist?('.env')}"
puts "DEBUG - MASTODON_BASE_URL: '#{ENV['MASTODON_BASE_URL']}'"
puts "DEBUG - MASTODON_TOKEN: 존재함" unless ENV['MASTODON_TOKEN'].to_s.strip.empty?

puts "[시작] 호그와트 교수봇 기동 중..."

# 마스토돈 설정 - 완전히 새로운 String 객체 생성
base_url = String.new(ENV['MASTODON_BASE_URL'].to_s)
token = String.new(ENV['MASTODON_TOKEN'].to_s)

puts "   BASE_URL: #{base_url}"
puts "   TOKEN 시작: #{token[0..10]}..." if token

# 디버깅용 상태 출력
puts "🔍 base_url = #{base_url.inspect} (#{base_url.class}, frozen?=#{base_url.frozen?})"
puts "🔍 token     = #{token.inspect} (#{token.class}, frozen?=#{token.frozen?})"

if base_url.nil? || base_url.strip.empty?
  raise "[오류] MASTODON_BASE_URL 환경변수가 비어 있습니다."
end

if token.nil? || token.strip.empty?
  raise "[오류] MASTODON_TOKEN 환경변수가 비어 있습니다."
end

# 시트 설정
puts "\n[시트] 설정 확인 중..."
session = GoogleDrive::Session.from_service_account_key("credentials.json")
puts "   인증 파일: credentials.json"
puts "   인증 파일 존재 확인" if File.exist?("credentials.json")

sheet_id = ENV['GOOGLE_SHEET_ID']
if sheet_id.nil? || sheet_id.strip.empty?
  raise "[오류] GOOGLE_SHEET_ID 환경변수가 비어 있습니다."
end

spreadsheet = session.spreadsheet_by_key(sheet_id)
puts "   시트 ID: #{sheet_id}"
puts "   ✅ 구글 시트 연결 성공: '#{spreadsheet.title}'"

# 마스토돈 연결
begin
  puts "\n[테스트] 마스토돈 연결..."
  
  # 추가 디버깅: URL과 토큰 재확인
  puts "🔧 DEBUG - URL 처리 전: #{base_url.inspect}"
  puts "🔧 DEBUG - TOKEN 처리 전: #{token[0..10]}..."
  
  # URL 정리
  clean_url = base_url.strip.chomp('/')
  clean_token = token.strip
  
  puts "🔧 DEBUG - URL 처리 후: #{clean_url.inspect}"
  puts "🔧 DEBUG - TOKEN 처리 후: #{clean_token[0..10]}..."
  puts "🔧 DEBUG - 처리 후 frozen 상태: url=#{clean_url.frozen?}, token=#{clean_token.frozen?}"
  
  client = Mastodon::REST::Client.new(
    base_url: clean_url,
    bearer_token: clean_token
  )
  
  puts "🔧 DEBUG - 클라이언트 생성 완료"
  account = client.verify_credentials
  puts "   ✅ 연결 성공! 계정: @#{account.acct}"
  
rescue => e
  puts "💥 연결 실패: #{e.message}"
  puts "💥 오류 클래스: #{e.class}"
  puts "💥 오류 스택:"
  puts e.backtrace[0..10].join("\n")
  puts "[실패] 마스토돈 연결 실패"
  exit 1
end

# 봇 시작
puts "\n[봇 시작] 호그와트 교수봇 활동 시작!"
puts "🎓 입학 신청 및 멘션 수신 대기 중..."

# 멘션 처리 변수 초기화
start_time = Time.now
mention_count = 0
error_count = 0
processed_mentions = Set.new

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
        content = mention.status.content.gsub(/<[^>]*>/, '').strip

        puts "\n🎓 멘션 ##{mention_count}"
        puts "   👤 학생: @#{user_acct}"
        puts "   📝 내용: #{content}"
        puts "   🕐 시간: #{mention.status.created_at rescue '알 수 없음'}"
        puts "   🆔 멘션 ID: #{mention_id}"

        CommandParser.handle(mention)
        puts "   ✅ 멘션 처리 완료"

      rescue => e
        error_count += 1
        puts "   ❌ 멘션 처리 실패: #{e.message}"
        puts "   📍 위치: #{e.backtrace.first}"

        # 오류 응답
        begin
          error_msg = "#{mention.account.display_name || mention.account.acct}님, 죄송합니다. 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요. 🎓"
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
    puts "\n[오류] 스트리밍 연결 오류: #{e.message}"
    puts "10초 후 재연결 시도..."
    sleep(10)
  end
end

# 종료 통계
end_time = Time.now
duration = end_time - start_time
h = (duration / 3600).to_i
m = ((duration % 3600) / 60).to_i
s = (duration % 60).to_i

puts "\n" + "="*50
puts "📊 [통계] 호그와트 교수봇 운영 리포트"
puts "="*50
puts "⏰ 총 운영 시간: #{h}시간 #{m}분 #{s}초"
puts "🎓 총 멘션 처리: #{mention_count}건"
puts "❌ 오류 발생: #{error_count}건"
puts "💾 처리된 멘션 ID: #{processed_mentions.size}개"
puts "📈 성공률: #{mention_count > 0 ? ((mention_count - error_count) * 100.0 / mention_count).round(1) : 0}%"
puts "="*50
puts "🎓 [완료] 호그와트 교수봇이 안전하게 종료되었습니다."
