# ============================================
# sheet_manager.rb (교수봇용 안정화 버전 - 완전판)
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
    response.values || []
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

  # ============================================
  # 🔹 학적부 관리 기능
  # ============================================

  # 특정 유저 찾기
  def find_user(username)
    data = read_range('플레이어!A:Z')
    header = data[0]
    return nil if data.size < 2

    username_col = header.index('아이디') || 0
    name_col = header.index('이름') || 1
    galleon_col = header.index('갈레온')
    house_score_col = header.index('개별 기숙사 점수')
    attend_col = header.index('출석날짜')

    row = data.find { |r| r[username_col].to_s.strip == username.strip }
    return nil unless row

    {
      id: row[username_col],
      name: row[name_col],
      galleon: galleon_col ? row[galleon_col].to_i : 0,
      house_score: house_score_col ? row[house_score_col].to_i : 0,
      attendance_date: attend_col ? row[attend_col].to_s : ''
    }
  rescue => e
    puts "[find_user 오류] #{e.message}"
    nil
  end

  # 유저의 특정 열 값을 증가시킴
  def increment_user_value(username, column_name, value)
    data = read_range('플레이어!A:Z')
    header = data[0]
    target_col = header.index(column_name)
    return if target_col.nil?

    data.each_with_index do |row, i|
      next if i.zero?
      next unless row[0].to_s.strip == username.strip

      current = row[target_col].to_i
      row[target_col] = current + value
      range = "플레이어!#{('A'..'Z').to_a[target_col]}#{i + 1}"
      write_range(range, [[row[target_col]]])
      puts "[시트 업데이트] #{username}의 #{column_name} → #{row[target_col]}"
      return
    end
  rescue => e
    puts "[increment_user_value 오류] #{e.message}"
  end

  # 유저의 특정 열 값을 설정
  def set_user_value(username, column_name, new_value)
    data = read_range('플레이어!A:Z')
    header = data[0]
    target_col = header.index(column_name)
    return if target_col.nil?

    data.each_with_index do |row, i|
      next if i.zero?
      next unless row[0].to_s.strip == username.strip

      row[target_col] = new_value
      range = "플레이어!#{('A'..'Z').to_a[target_col]}#{i + 1}"
      write_range(range, [[new_value]])
      puts "[시트 설정] #{username}의 #{column_name} = #{new_value}"
      return
    end
  rescue => e
    puts "[set_user_value 오류] #{e.message}"
  end
end
