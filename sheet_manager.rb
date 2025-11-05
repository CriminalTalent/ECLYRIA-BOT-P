# /root/mastodon_bots/professor_bot/sheet_manager.rb
# ==============================================
# Google Sheets 연동 모듈
# ==============================================

require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  attr_reader :service, :sheet_id

  def initialize(sheet_id)
    @sheet_id = sheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.client_options.application_name = "Professor Bot"
    @service.authorization = authorize_service_account
  end

  # ----------------------------------------------
  # Google Service Account 인증
  # ----------------------------------------------
  def authorize_service_account
    scope = ["https://www.googleapis.com/auth/spreadsheets"]
    keyfile = File.expand_path("../credentials.json", __dir__)
    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(keyfile),
      scope: scope
    )
  end

  # ----------------------------------------------
  # 시트 읽기 / 쓰기
  # ----------------------------------------------
  def read(range)
    response = @service.get_spreadsheet_values(@sheet_id, range)
    response.values || []
  rescue => e
    puts "[시트 읽기 실패] #{e.message}"
    []
  end

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

  # ----------------------------------------------
  # 사용자 검색 (ID 기준)
  # ----------------------------------------------
  def find_user(user_id)
    data = read('사용자!A2:H')
    data.each do |row|
      return {
        id: row[0],
        name: row[1],
        galleon: row[2].to_i,
        house: row[4],
        memo: row[5],
        homework_date: row[6],
        attendance_date: row[7]
      } if row[0].to_s.strip == user_id.to_s.strip
    end
    nil
  end

  # ----------------------------------------------
  # 셀 값 변경 / 증가
  # ----------------------------------------------
  def set_user_value(user_id, column_name, value)
    header = read('사용자!A1:H1').first
    col_index = header.index(column_name)
    return puts "[에러] '#{column_name}' 열을 찾을 수 없음" unless col_index

    data = read('사용자!A2:H')
    data.each_with_index do |row, i|
      if row[0].to_s.strip == user_id.to_s.strip
        cell = "#{('A'..'Z').to_a[col_index]}#{i + 2}"
        write("사용자!#{cell}", [[value]])
        return
      end
    end
    puts "[에러] 사용자 #{user_id} 를 찾을 수 없음"
  end

  def increment_user_value(user_id, column_name, amount)
    header = read('사용자!A1:H1').first
    col_index = header.index(column_name)
    return puts "[에러] '#{column_name}' 열을 찾을 수 없음" unless col_index

    data = read('사용자!A2:H')
    data.each_with_index do |row, i|
      if row[0].to_s.strip == user_id.to_s.strip
        current = row[col_index].to_i
        new_val = current + amount
        cell = "#{('A'..'Z').to_a[col_index]}#{i + 2}"
        write("사용자!#{cell}", [[new_val]])
        return
      end
    end
  end
end
