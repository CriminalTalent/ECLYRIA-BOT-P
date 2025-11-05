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

require_relative 'sheet_manager'
require_relative 'professor_command_parser'
require_relative 'utils/house_score_updater'

# ----------------------------------------------
# 환경 변수 로드 (.env)
# ----------------------------------------------
ENV_PATH = File.expand_path('../.env', __dir__)
if File.exist?(ENV_PATH)
  File.readlines(ENV_PATH, chomp: true).each do |line|
    key, value = line.split('=', 2)
    ENV[key] = value if key && value
  end
end

MASTODON_DOMAIN = ENV['MASTODON_DOMAIN']
ACCESS_TOKEN = ENV['ACCESS_TOKEN']
SHEET_ID = ENV['SHEET_ID']

MENTION_ENDPOINT = "https://#{MASTODON_DOMAIN}/api/v1/notifications"
POST_ENDPOINT = "https://#{MASTODON_DOMAIN}/api/v1/statuses"

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
def fetch_mentions
  uri = URI("#{MENTION_ENDPOINT}?types[]=mention")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{ACCESS_TOKEN}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  return [] unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
rescue => e
  puts "[에러] 멘션 불러오기 실패: #{e.message}"
  []
end

def reply_to_mention(content, in_reply_to_id)
  uri = URI(POST_ENDPOINT)
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{ACCESS_TOKEN}"
  req.set_form_data('status' => content, 'in_reply_to_id' => in_reply_to_id, 'visibility' => 'unlisted')

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
rescue => e
  puts "[에러] 답글 전송 실패: #{e.message}"
end

# ----------------------------------------------
# Mentions 감시 루프
# ----------------------------------------------
last_checked = Time.now - 60
loop do
  mentions = fetch_mentions
  mentions.each do |mention|
    created_at = Time.parse(mention['created_at'])
    next if created_at <= last_checked

    text = mention['status']['content'].gsub(/<[^>]*>/, '').strip
    toot_id = mention['status']['id']
    sender = mention['account']['acct']

    puts "[MENTION] #{sender}: #{text}"

    # 명령어 실행
    result = ProfessorParser.parse(sheet_manager, sender, text)
    reply_to_mention(result, toot_id) if result && !result.empty?
  end

  last_checked = Time.now
  sleep 30
end
