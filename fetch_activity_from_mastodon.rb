# fetch_activity_from_mastodon.rb - 마스토돈에서 실제 활동 내역 가져오기
require 'bundler/setup'
Bundler.require
require 'dotenv'
Dotenv.load('.env')
require 'mastodon'
require 'date'

puts "=========================================="
puts "마스토돈에서 활동 내역 가져오기"
puts "=========================================="

SHEET_ID = ENV["SHEET_ID"] || ENV["GOOGLE_SHEET_ID"]

# 마스토돈 설정 확인
base_url = ENV['MASTODON_BASE_URL'] || ENV['MASTODON_DOMAIN']
token = ENV['MASTODON_TOKEN'] || ENV['ACCESS_TOKEN']

# base_url에 https:// 추가 (없는 경우)
unless base_url.to_s.start_with?('http')
  base_url = "https://#{base_url}"
end

puts "[확인] 마스토돈 서버: #{base_url}"
puts "[확인] 토큰: #{token[0..10]}..."

unless token
  puts "[오류] 마스토돈 토큰이 설정되지 않았습니다."
  exit
end

# 마스토돈 클라이언트 생성
begin
  client = Mastodon::REST::Client.new(
    base_url: base_url,
    bearer_token: token
  )
  puts "[성공] 마스토돈 클라이언트 생성 완료"
rescue => e
  puts "[오류] 마스토돈 클라이언트 생성 실패: #{e.message}"
  exit
end
