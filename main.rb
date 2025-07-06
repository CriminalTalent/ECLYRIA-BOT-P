# frozen_string_literal: false
require 'dotenv/load'
require 'mastodon'
require 'google_drive'
require 'json'

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
end
