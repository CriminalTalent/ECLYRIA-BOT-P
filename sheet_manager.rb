# sheet_manager.rb (교수봇용 완전 수정 버전 - K열 지원)
require 'google/apis/sheets_v4'

class SheetManager
  attr_reader :service, :sheet_id

  USERS_SHEET = '사용자'.freeze
  PROFESSOR_SHEET = '교수'.freeze
  HOUSE_SHEET = '기숙사'.freeze

  def initialize(service, sheet_id)
    @service = service
    @sheet_id = sheet_id
  end

  # 기본 read 메서드
  def read(sheet_name, a1 = 'A:Z')
    ensure_separate_args!(sheet_name, a1)
    read_range(a1_range(sheet_name, a1))
  end

  # 기본 write 메서드
  def write(sheet_name, a1, values)
    ensure_separate_args!(sheet_name, a1)
    write_range(a1_range(sheet_name, a1), values)
  end

  # 기본 append 메서드
  def append(sheet_name, row)
    ensure_separate_args!(sheet_name, 'A:Z')
    append_log(sheet_name, row)
  end

  # A1 범위 생성
  def a1_range(sheet_name, a1 = 'A:Z')
    sh = sheet_name.to_s
    if sh.include?('!')
      base, rng_from_name = sh.split('!', 2)
      rng = (a1 && a1.strip != '' && a1 != 'A:Z') ? a1 : rng_from_name
      escaped = base.gsub("'", "''")
      "'#{escaped}'!#{rng}"
    else
      escaped = sh.gsub("'", "''")
      "'#{escaped}'!#{a1}"
    end
  end

  # 열 인덱스를 A1 형식으로 변환
  def col_idx_to_a1(idx)
    s = ''
    n = idx
    while n >= 0
      s = (65 + (n % 26)).chr + s
      n = (n / 26) - 1
    end
    s
  end

  # 시트 읽기
  def read_range(range)
    response = @service.get_spreadsheet_values(@sheet_id, range)
    response.values || []
  rescue => e
    puts "[시트 읽기 오류] #{e.message}"
    []
  end

  # 시트 쓰기
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

  # 로그 추가
  def append_log(sheet_name, row)
    range = a1_range(sheet_name, 'A:Z')
    body = Google::Apis::SheetsV4::ValueRange.new(values: [row])

    @service.append_spreadsheet_value(
      @sheet_id,
      range,
      body,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 로그 추가 오류] #{e.message}"
  end

  # 사용자 찾기 (A:K 범위 - K열까지 포함)
  def find_user(username)
    clean_username = username.to_s.gsub('@', '').strip
    data = read_range(a1_range(USERS_SHEET, 'A:K'))
    return nil if data.empty?

    header = data[0] || []
    return nil if data.size < 2

    puts "[FIND_USER] 헤더: #{header.inspect}"
    puts "[FIND_USER] 검색 ID: #{clean_username}"

    # 열 매핑
    # A: 사용자ID, B: 이름, C: 갈레온, D: 아이템, E: 메모, F: 기숙사
    # G: 마지막베팅일, H: 오늘베팅횟수, I: 출석날짜, J: 마지막타로일, K: 개별기숙사점수
    username_col = 0
    name_col = 1
    galleon_col = 2
    items_col = 3
    memo_col = 4
    house_col = 5
    last_bet_date_col = 6
    today_bet_count_col = 7
    attendance_date_col = 8
    last_tarot_date_col = 9
    house_score_col = 10

    data.each_with_index do |row, i|
      next if i == 0
      next if row.nil? || row[username_col].nil?
      
      row_id = row[username_col].to_s.gsub('@', '').strip
      
      if row_id == clean_username
        puts "[FIND_USER] 찾음: #{clean_username} (행: #{i+1})"
        return {
          row_index: i,
          id: row[username_col].to_s.strip,
          name: row[name_col].to_s.strip,
          galleons: (row[galleon_col] || 0).to_i,
          items: (row[items_col] || "").to_s.strip,
          memo: (row[memo_col] || "").to_s.strip,
          house: (row[house_col] || "").to_s.strip,
          last_bet_date: (row[last_bet_date_col] || "").to_s.strip,
          today_bet_count: (row[today_bet_count_col] || 0).to_i,
          attendance_date: (row[attendance_date_col] || "").to_s.strip,
          last_tarot_date: (row[last_tarot_date_col] || "").to_s.strip,
          house_score: (row[house_score_col] || 0).to_i
        }
      end
    end

    puts "[FIND_USER] 못 찾음: #{clean_username}"
    nil
  rescue => e
    puts "[find_user 오류] #{e.message}"
    puts e.backtrace.first(3)
    nil
  end

  # 사용자 데이터 업데이트
  def update_user(user_id, data)
    user = find_user(user_id)
    return false unless user
    
    puts "[UPDATE_USER] 업데이트 대상: 행#{user[:row_index]}, ID=#{user_id}"
    
    # Google Sheets는 1-based index
    sheet_row = user[:row_index] + 1
    
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
    
    range = a1_range(USERS_SHEET, "A#{sheet_row}:K#{sheet_row}")
    puts "[UPDATE_USER] 전체 행 업데이트: #{range}"
    
    write_range(range, [row_data])
    puts "[UPDATE_USER] 업데이트 완료: #{user_id}, #{data.inspect}"
    true
  rescue => e
    puts "[update_user 오류] #{e.message}"
    puts e.backtrace.first(3)
    false
  end

  # 값 증가
  def increment_user_value(user_id, field, amount)
    user = find_user(user_id)
    return false unless user
    
    puts "[INCREMENT] #{field} +#{amount} for #{user_id}"
    
    case field
    when "갈레온"
      update_user(user_id, galleons: user[:galleons] + amount)
    when "개별 기숙사 점수"
      update_user(user_id, house_score: user[:house_score] + amount)
    else
      puts "[INCREMENT] 알 수 없는 필드: #{field}"
      false
    end
  end

  # 값 설정
  def set_user_value(user_id, field, value)
    user = find_user(user_id)
    return false unless user
    
    puts "[SET_VALUE] #{field} = #{value} for #{user_id}"
    
    case field
    when "출석날짜"
      update_user(user_id, attendance_date: value)
    when "과제날짜"
      update_user(user_id, last_bet_date: value)
    else
      puts "[SET_VALUE] 알 수 없는 필드: #{field}"
      false
    end
  end

  # 사용자 행 추가
  def add_user_row(user_data)
    append_log(USERS_SHEET, user_data)
  end

  # 교수 설정 확인
  def auto_push_enabled?(key: '아침출석자동툿')
    range = a1_range(PROFESSOR_SHEET, 'A1:Z2')
    data = read_range(range)

    return false if data.empty? || data[0].nil?

    header = data[0]
    values = data[1] || []

    normalized_key = key.to_s.strip.unicode_normalize(:nfkc)

    header_index = header.index { |h| h.to_s.strip.unicode_normalize(:nfkc) == normalized_key }
    return false if header_index.nil?

    val = values[header_index]

    if val == true ||
       val.to_s.strip.upcase == 'TRUE' ||
       %w[ON YES 1].include?(val.to_s.strip.upcase)
      true
    else
      false
    end
  rescue => e
    puts "[auto_push_enabled? 오류] #{e.message}"
    false
  end

  # 기숙사 점수 업데이트 (utils/house_score_updater.rb 호환)
  def update_house_score(house_name, points)
    return if house_name.nil? || house_name.strip.empty?
    house_name = house_name.strip

    data = read_range(a1_range(HOUSE_SHEET, 'A:B'))
    return if data.empty?

    data.each_with_index do |row, i|
      next if i == 0
      next if row.nil? || row[0].nil?
      
      if row[0].to_s.strip == house_name
        current_score = (row[1] || 0).to_i
        new_score = current_score + points
        
        range = a1_range(HOUSE_SHEET, "B#{i+1}")
        write_range(range, [[new_score]])
        
        puts "[기숙사 점수] #{house_name} → +#{points}점 (총합: #{new_score})"
        return
      end
    end
  rescue => e
    puts "[update_house_score 오류] #{e.message}"
  end

  # 호환성 메서드들
  def read_values(range)
    sheet_name = range.include?('!') ? range.split('!').first : USERS_SHEET
    a1 = range.split('!').last || 'A:Z'
    read(sheet_name, a1)
  end

  def update_values(range, values)
    sheet_name = range.include?('!') ? range.split('!').first : USERS_SHEET
    a1 = range.split('!').last || range
    write(sheet_name, a1, values)
  end

  def append_values(range, values)
    sheet_name = range.include?('!') ? range.split('!').first : USERS_SHEET
    values.each { |row| append(sheet_name, row) }
  end

  def worksheet_by_title(title)
    WorksheetWrapper.new(self, title)
  end

  private

  def ensure_separate_args!(sheet_name, a1)
    unless sheet_name.is_a?(String) && !sheet_name.strip.empty?
      raise ArgumentError, "시트 이름이 유효하지 않습니다."
    end
    unless a1.is_a?(String) && !a1.strip.empty?
      raise ArgumentError, "A1 범위가 유효하지 않습니다."
    end
  end
end

# 구식 워크시트 객체 래퍼 클래스
class WorksheetWrapper
  def initialize(sheet_manager, title)
    @sheet_manager = sheet_manager
    @title = title
    @data = nil
    load_data
  end

  def load_data
    @data = @sheet_manager.read(@title, 'A:Z')
    @data ||= []
  end

  def save
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
    while @data.length < row
      @data << []
    end
    while @data[row-1].length < col
      @data[row-1] << ""
    end
    
    @data[row-1][col-1] = value
    
    cell_range = "#{@title}!#{column_letter(col)}#{row}"
    @sheet_manager.write_range(@sheet_manager.a1_range(@title, "#{column_letter(col)}#{row}"), [[value]])
  end

  def insert_rows(at_row, rows_data)
    puts "[DEBUG] WorksheetWrapper.insert_rows 호출됨: #{rows_data.inspect}"
    range = @sheet_manager.a1_range(@title, 'A:Z')
    rows_data.each { |row| @sheet_manager.append_log(@title, row) }
    load_data
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
