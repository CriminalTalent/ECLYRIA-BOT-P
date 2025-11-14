# ============================================
# sheet_manager.rb (교수봇용 완전 안정 버전)
# google-api-client 기반 / append 충돌 해결판
# ============================================

require 'google/apis/sheets_v4'

class SheetManager
  attr_reader :service, :sheet_id

  USERS_SHEET = '사용자'.freeze
  PROFESSOR_SHEET = '교수'.freeze

  def initialize(service, sheet_id)
    @service = service
    @sheet_id = sheet_id
  end

  # ============================================
  # 기본 입출력
  # ============================================

  def read(sheet_name, a1 = 'A:Z')
    ensure_separate_args!(sheet_name, a1)
    read_range(a1_range(sheet_name, a1))
  end

  def write(sheet_name, a1, values)
    ensure_separate_args!(sheet_name, a1)
    write_range(a1_range(sheet_name, a1), values)
  end

  def append(sheet_name, row)
    ensure_separate_args!(sheet_name, 'A:Z')
    append_log(sheet_name, row)
  end


  # ============================================
  # A1 유틸
  # ============================================

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

  def col_idx_to_a1(idx)
    s = ''
    n = idx
    while n >= 0
      s = (65 + (n % 26)).chr + s
      n = (n / 26) - 1
    end
    s
  end


  # ============================================
  # 공통 I/O 동작
  # ============================================

  def read_range(range)
    response = @service.get_spreadsheet_values(@sheet_id, range)
    response.values || []
  rescue => e
    puts "[시트 읽기 오류] #{e.message}"
    []
  end

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


  # ============================================
  # 학적부 관리 기능
  # ============================================

  def find_user(username)
    data = read_range(a1_range(USERS_SHEET, 'A:Z'))
    return nil if data.empty?

    header = data[0] || []
    return nil if data.size < 2

    username_col     = header.index('아이디') || 0
    name_col         = header.index('이름')   || 1
    galleon_col      = header.index('갈레온')
    house_score_col  = header.index('개별 기숙사 점수')
    attend_col       = header.index('출석날짜')

    row = data.find.with_index { |r, i| i > 0 && r[username_col].to_s.strip == username.strip }
    return nil unless row

    {
      id:              row[username_col],
      name:            row[name_col],
      galleon:         galleon_col     ? row[galleon_col].to_i : 0,
      house_score:     house_score_col ? row[house_score_col].to_i : 0,
      attendance_date: attend_col      ? row[attend_col].to_s : ''
    }
  rescue => e
    puts "[find_user 오류] #{e.message}"
    nil
  end


  def increment_user_value(username, column_name, value)
    data = read_range(a1_range(USERS_SHEET, 'A:Z'))
    return if data.empty?
    header = data[0] || []

    target_col = header.index(column_name)
    return if target_col.nil?

    username_col = header.index('아이디') || 0

    data.each_with_index do |row, i|
      next if i.zero?
      next unless row[username_col].to_s.strip == username.strip

      current = (row[target_col] || 0).to_i
      new_val = current + value

      col_letter = col_idx_to_a1(target_col)
      cell_range = a1_range(USERS_SHEET, "#{col_letter}#{i + 1}")

      write_range(cell_range, [[new_val]])
      puts "[시트 업데이트] #{username}의 #{column_name} → #{new_val}"
      return
    end
  rescue => e
    puts "[increment_user_value 오류] #{e.message}"
  end


  def set_user_value(username, column_name, new_value)
    data = read_range(a1_range(USERS_SHEET, 'A:Z'))
    return if data.empty?
    header = data[0] || []

    target_col = header.index(column_name)
    return if target_col.nil?

    username_col = header.index('아이디') || 0

    data.each_with_index do |row, i|
      next if i.zero?
      next unless row[username_col].to_s.strip == username.strip

      col_letter = col_idx_to_a1(target_col)
      cell_range = a1_range(USERS_SHEET, "#{col_letter}#{i + 1}")

      write_range(cell_range, [[new_value]])
      puts "[시트 설정] #{username}의 #{column_name} = #{new_value}"
      return
    end
  rescue => e
    puts "[set_user_value 오류] #{e.message}"
  end


  # ============================================
  # 자동 멘트 발송 ON/OFF 확인
  # ============================================

  def auto_push_enabled?(key: '아침출석자동툿')
    range = a1_range(PROFESSOR_SHEET, 'A1:Z2')
    data  = read_range(range)

    return false if data.empty? || data[0].nil?

    header = data[0]
    values = data[1] || []

    normalized_key = key.to_s.strip.unicode_normalize(:nfkc)

    header_index = header.index { |h| h.to_s.strip.unicode_normalize(:nfkc) == normalized_key }
    return false if header_index.nil?

    val = values[header_index]

    if val == true ||
       val.to_s.strip.upcase == 'TRUE' ||
       %w[ON YES 1 ☑].include?(val.to_s.strip.upcase)
      true
    else
      false
    end
  rescue => e
    puts "[auto_push_enabled? 오류] #{e.message}"
    false
  end


  # ============================================
  # PRIVATE
  # ============================================

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
