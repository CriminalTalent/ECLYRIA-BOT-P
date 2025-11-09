# ============================================
# sheet_manager.rb (교수봇용 안정화 버전)
# ============================================
require 'google/apis/sheets_v4'

class SheetManager
  attr_reader :service, :sheet_id

  def initialize(service, sheet_id)
    @service = service
    @sheet_id = sheet_id
  end

  # 시트의 특정 범위 읽기
  def read_range(range)
    response = @service.get_spreadsheet_values(@sheet_id, range)
    response.values
  rescue => e
    puts "[시트 읽기 오류] #{e.message}"
    []
  end

  # 시트의 특정 범위 쓰기
  def write_range(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 쓰기 오류] #{e.message}"
  end

  # 로그 남기기 (예: 출석, 과제 기록)
  def append_log(sheet_name, row)
    range = "#{sheet_name}!A:Z"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [row])
    @service.append_spreadsheet_value(
      @sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 로그 추가 오류] #{e.message}"
  end
end
