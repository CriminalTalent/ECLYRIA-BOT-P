# sheet_manager.rb
require 'google/apis/sheets_v4'

class SheetManager
  def initialize(sheets_service, sheet_id)
    @service = sheets_service
    @sheet_id = sheet_id
    @worksheets_cache = {}
  end

  # 기존 API v4 메서드들
  def read_values(range)
    @service.get_spreadsheet_values(@sheet_id, range).values
  rescue => e
    puts "시트 읽기 오류: #{e.message}"
    []
  end

  def update_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(@sheet_id, range, value_range, value_input_option: 'USER_ENTERED')
  rescue => e
    puts "시트 쓰기 오류: #{e.message}"
  end

  def append_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.append_spreadsheet_value(@sheet_id, range, value_range, value_input_option: 'USER_ENTERED')
  rescue => e
    puts "시트 추가 오류: #{e.message}"
  end

  # 구식 google_drive gem 호환 메서드들
  def worksheet_by_title(title)
    @worksheets_cache[title] ||= WorksheetWrapper.new(self, title)
  end

  def find_user(user_id)
    values = read_values("사용자!A:K")
    return nil if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      if row[0] == user_id
        return {
          row_index: index + 1,
          id: row[0],
          name: row[1],
          galleons: row[2].to_i,
          items: row[3] || "",
          memo: row[4] || "",
          house: row[5] || "",
          last_bet_date: row[6] || "",
          today_bet_count: row[7] || "",
          attendance_date: row[8] || "",
          last_tarot_date: row[9] || "",
          house_score: row[10].to_i
        }
      end
    end
    nil
  end

  # 사용자 데이터 업데이트
  def update_user(user_id, data)
    user = find_user(user_id)
    return false unless user
    
    row_data = [
      user_id,
      data[:name] || user[:name],
      data[:galleons] || user[:galleons],
      data[:items] || user[:items],
      data[:memo] || user[:memo],
      data[:house] || user[:house],
      data[:last_bet_date] || user[:last_bet_date],
      data[:today_bet_count] || user[:today_bet_count],
      data[:attendance_date] || user[:attendance_date],
      data[:last_tarot_date] || user[:last_tarot_date],
      data[:house_score] || user[:house_score]
    ]
    
    update_values("사용자!A#{user[:row_index] + 1}:K#{user[:row_index] + 1}", [row_data])
    true
  end

  # AttendanceCommand를 위한 메서드들
  def increment_user_value(user_id, field, amount)
    user = find_user(user_id)
    return false unless user
    
    case field
    when "갈레온"
      update_user(user_id, galleons: user[:galleons] + amount)
    when "개별 기숙사 점수"
      update_user(user_id, house_score: user[:house_score] + amount)
    else
      false
    end
  end

  def set_user_value(user_id, field, value)
    user = find_user(user_id)
    return false unless user
    
    case field
    when "출석날짜"
      update_user(user_id, attendance_date: value)
    when "과제날짜"
      update_user(user_id, last_bet_date: value) # 임시로 이 필드 사용
    else
      false
    end
  end

  # HomeworkCommand를 위한 메서드
  def add_user_row(user_data)
    append_values("사용자!A:K", [user_data])
  end
end

# 구식 워크시트 객체를 흉내내는 래퍼 클래스
class WorksheetWrapper
  def initialize(sheet_manager, title)
    @sheet_manager = sheet_manager
    @title = title
    @data = nil
    load_data
  end

  def load_data
    @data = @sheet_manager.read_values("#{@title}!A:Z")
    @data ||= []
  end

  def save
    # 새로운 API에서는 즉시 저장되므로 별도 작업 불필요
    true
  end

  def num_rows
    load_data
    @data.length
  end

  def [](row, col)
    load_data
    return nil if row < 1 || row > @data.length
    return nil if col < 1 || col > (@data[row-1]&.length || 0)
    @data[row-1][col-1]
  end

  def []=(row, col, value)
    load_data
    # 행이나 열이 부족하면 확장
    while @data.length < row
      @data << []
    end
    while @data[row-1].length < col
      @data[row-1] << ""
    end
    
    @data[row-1][col-1] = value
    
    # 즉시 업데이트
    cell_range = "#{@title}!#{column_letter(col)}#{row}"
    @sheet_manager.update_values(cell_range, [[value]])
  end

  def insert_rows(at_row, rows_data)
    # 새 행을 추가하는 방식으로 구현
    range = "#{@title}!A#{at_row}"
    @sheet_manager.append_values(range, rows_data)
    load_data # 데이터 새로고침
  end

  private

  def column_letter(col_num)
    result = ""
    while col_num > 0
      col_num -= 1
      result = ((col_num % 26) + 65).chr + result
      col_num /= 26
    end
    result
  end
end
