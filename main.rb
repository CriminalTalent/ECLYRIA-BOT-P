# /root/mastodon_bots/professor_bot/main.rb
# ==============================================
# Mastodon Professor Bot - Google Sheets 연동
# ==============================================

require 'google/apis/sheets_v4'
require 'googleauth'
require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'dotenv'

require_relative 'sheet_manager'
require_relative 'professor_command_parser'
require_relative 'utils/house_score_updater'

Dotenv.load(File.expand_path('../.env', __dir__))

MASTODON_DOMAIN = ENV['MASTODON_DOMAIN']
ACCESS_TOKEN     = ENV['ACCESS_TOKEN']
SHEET_ID         = ENV['SHEET_ID']
LAST_ID_FILE     = File.expand_path('last_mention_id.txt', __dir__)

if MASTODON_DOMAIN.nil? || MASTODON_DOMAIN.strip.empty?
  puts "[에러] MASTODON_DOMAIN 값이 비어 있습니다. .env 파일을 확인하세요."
  exit
end

MENTION_ENDPOINT = "https://#{MASTODON_DOMAIN}/api/v1/notifications"
POST_ENDPOINT    = "https://#{MASTODON_DOMAIN}/api/v1/statuses"

puts "[교수봇] 실행 시작 (#{Time.now.strftime('%H:%M:%S')})"

# ----------------------------------------------
# Google Sheets 연결
# ----------------------------------------------
sheet_manager = nil
begin
  sheet_manager = SheetManager.new(SHEET_ID)
  puts "Google Sheets 연결 성공"
rescue => e
  puts "Google Sheets 연결 실패: #{e.message}"
  exit
end

# ----------------------------------------------
# Mastodon Mentions 처리 함수
# ----------------------------------------------
def fetch_mentions(since_id = nil)
  base_url = "#{MENTION_ENDPOINT}?types[]=mention&limit=20"
  url = since_id ? "#{base_url}&since_id=#{since_id}" : base_url
  uri = URI(url)

  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{ACCESS_TOKEN}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end

  if res.code == '429'
    raise "429 Too Many Requests"
  end

  return [] unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
rescue => e
  puts "[에러] 멘션 불러오기 실패: #{e.message}"
  []
end

def reply_to_mention(content, in_reply_to_id)
  return if content.nil? || content.strip.empty?

  uri = URI(POST_ENDPOINT)
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{ACCESS_TOKEN}"
  req.set_form_data(
    'status' => content,
    'in_reply_to_id' => in_reply_to_id,
    'visibility' => 'unlisted'
  )

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
rescue => e
  puts "[에러] 답글 전송 실패: #{e.message}"
end

# ----------------------------------------------
# Mentions 감시 루프 (since_id + 429 대응)
# ----------------------------------------------
last_id = File.exist?(LAST_ID_FILE) ? File.read(LAST_ID_FILE).strip : nil

loop do
  begin
    mentions = fetch_mentions(last_id)
    mentions.sort_by! { |m| m['id'].to_i }

    mentions.each do |mention|
      next unless mention['status']
      created_at = Time.parse(mention['created_at']).getlocal
      text = mention['status']['content'].gsub(/<[^>]*>/, '').strip
      toot_id = mention['status']['id']
      sender = mention['account']['acct']

      puts "[MENTION] #{created_at.strftime('%H:%M:%S')} - @#{sender}: #{text}"

      result = ProfessorParser.parse(sheet_manager, sender, text)
      reply_to_mention(result, toot_id) if result && !result.empty?

      last_id = mention['id']
      File.write(LAST_ID_FILE, last_id)
    end

  rescue => e
    if e.message.include?('429') || e.message.include?('Too Many Requests')
      puts "[경고] 429 Too Many Requests 발생 → 5분 대기"
      sleep 300
    else
      puts "[에러] Mentions 처리 중 오류: #{e.message}"
      sleep 60
    end
    retry
  end

  sleep 60 + rand(-5..5)
end
