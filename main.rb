# main.rb
require_relative './mastodon_client'
require_relative './sheet_manager'
require_relative './professor_command_parser'

require 'dotenv'
Dotenv.load

puts "[교수봇] 실행 시작"

# 마스토돈 클라이언트 초기화
mastodon = MastodonClient.new(
  base_url: ENV['MASTODON_BASE_URL'],
  token: ENV['MASTODON_TOKEN']
)

# 구글 시트 매니저 초기화
sheet_manager = SheetManager.new(ENV['GOOGLE_SHEET_ID'])

# 멘션 스트리밍 시작
mastodon.stream_user do |mention|
  begin
    # 멘션을 교수 파서로 전달
    ProfessorParser.parse(mastodon, sheet_manager, mention)
  rescue => e
    puts "[에러] 처리 중 예외 발생: #{e.message}"
    puts e.backtrace
  end
end
