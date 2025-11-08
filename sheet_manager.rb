# /root/mastodon_bots/professor_bot/sheet_manager.rb
require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  attr_reader :service, :sheet_id

  def initialize(sheet_id)
    @sheet_id = sheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.client_options.application_name = "Professor Bot"
    @service.authorization = authorize_service_account
  rescue => e
    puts "Google Sheets 연결 실패: #{e.message}"
  end

  private

  def authorize_service_account
    scope = ["https://www.googleapis.com/auth/spreadsheets"]

    # ✅ credentials.json 경로를 /root/mastodon_bots/professor_bot/로 고정
    keyfile = File.expand_path("../credentials.json", __dir__)

    unless File.exist?(keyfile)
      raise "credentials.json 파일을 찾을 수 없습니다 (#{keyfile})"
    end

    creds = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(keyfile),
      scope: scope
    )
    creds.fetch_access_token!
    creds
  end

  public

  # ✅ 시트 읽기 (에러 시 빈 배열 반환)
  def read(range)
    result = @service.get_spreadsheet_values(@sheet_id, range)
    result.values || []
  rescue => e
    puts "[시트 읽기 실패] #{e.message}"
    []
  end

  # ✅ 시트 쓰기
  def write(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 쓰기 실패] #{e.message}"
  end

  # ✅ 시트 행 추가 (로그 등 기록용)
  def append(range, values)
    body = Google::Apis::SheetsV4::ValueRange.new(values: [values])
    @service.append_spreadsheet_value(
      @sheet_id,
      range,
      body,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 추가 실패] #{e.message}"
  end
end
