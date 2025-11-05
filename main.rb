# /root/mastodon_bots/professor_bot/main.rb
# =========================================================
# 마스토돈 교수봇: Google Sheets 연동 + Mentions 처리 + 자동 점수 반영
# =========================================================

require 'google/apis/sheets_v4'
require 'googleauth'
require 'json'
require 'net/http'
require 'uri'
require 'time'

require_relative 'sheet_manager'
require_relative 'utils/house_score_updater'
require_relative 'command_parser'

# 환경 변수 로드
ENV_PATH = File.expand_path('../.env', __dir__)
if File.exist?(ENV_PATH)
  File.readlines(ENV_PATH, chomp: true).each do |line|
    key, value = line.split('=', 2)
    ENV[key] = value if key && value
  end
end

# =========================================================
# 마스토돈 봇 기본 설정
# =========================================================
MASTODON_DOMAIN = ENV['MASTODON_DOMAIN']
ACCESS_TOKEN = ENV['ACCESS_TOKEN']
SHEET_ID = ENV['SHEET_ID']

MENTION_ENDPOINT = "https://#{MASTODON_DOMAIN}/api/v1/notifications"
POST_ENDPOINT = "https://#{MASTODON_DOMAIN}/api/v1/statuses"

puts "[교수봇] 실행 시작 (#{Time.now.strftime('%H:%M:%S')})"

# =========================================================
# Google Sheets 연결
# =========================================================
sheet_manager = nil
begin
  sheet_manager = SheetManager.new(SHEET_ID)
  puts "Google Sheets 연결 성공: 교수봇"
rescue => e
  puts "Google Sheets 연결 실패: #{e.message}"
  exit
end

# =========================================================
# 명령어 파서 초기화
# =========================================================
parser = CommandParser.new(sheet_manager)

# =========================================================
# Mentions 감시 루프
# =========================================================
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

# =========================================================
# 주기적 실행 루프
# =========================================================
last_checked = Time.now - 60
loop do
  mentions = fetch_mentions
  mentions.each do |mention|
    created_at = Time.parse(mention['created_at'])
    next if created_at <= last_checked

    content = mention['status']['content'].gsub(/<[^>]*>/, '').strip
    toot_id = mention['status']['id']
    account = mention['account']['acct']

    puts "[MENTION] #{account}: #{content}"

    response = parser.parse_command(account, content)
    reply_to_mention(response, toot_id) if response && !response.empty?
  end

  last_checked = Time.now
  sleep 30
end
