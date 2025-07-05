# command_parser.rb (교수봇)
require_relative 'mastodon_client'
require 'google_drive'
require 'json'
require 'time'

module CommandParser
  # 구글 시트 워크시트 이름
  USERS_SHEET = '사용자'        # 상점봇과 공유
  RESPONSES_SHEET = '응답'      # 상점봇과 공유  
  HOUSES_SHEET = '기숙사점수'    # 교수봇 전용
  
  # 기숙사 목록
  HOUSES = ['그리핀도르', '슬리데린', '레번클로', '후플푸프']
  
  def self.handle(mention)
    text = mention.status.content
                   .gsub(/<[^>]*>/, '')
                   .strip
    
    acct = mention.account.acct
    display_name = mention.account.display_name || acct
    
    puts "처리 중인 멘션: #{text}"
    
    # 교수봇 명령어 처리
    case text
    when /^\[입학\/(.+)\]$/i
      handle_enrollment(mention, acct, display_name, $1)
    when /^\[출석\]$/i, /^출석$/i
      handle_attendance(mention, acct, display_name)
    when /^\[과제\]$/i, /^과제$/i
      handle_assignment(mention, acct, display_name)
    else
      handle_unknown(mention, acct, display_name, text)
    end
  end

  private

  # 구글 시트 클라이언트
  def self.google_client
    @google_client ||= begin
      credentials_path = ENV['GOOGLE_CREDENTIALS_PATH']
      unless File.exist?(credentials_path)
        raise "구글 인증 파일을 찾을 수 없습니다: #{credentials_path}"
      end
      
      GoogleDrive::Session.from_service_account_key(credentials_path)
    end
  end

  # 구글 스프레드시트 가져오기
  def self.spreadsheet
    @spreadsheet ||= begin
      sheet_id = ENV['GOOGLE_SHEET_ID']
      google_client.spreadsheet_by_key(sheet_id)
    end
  end

  # 자동 출석 메시지 가져오기 (매일 9시용 - 날씨 포함)
  def self.get_daily_attendance_message
    begin
      # 날씨 정보 생성
      weather_info = generate_weather_info
      
      worksheet = spreadsheet.worksheet_by_title(RESPONSES_SHEET)
      attendance_messages = []
      
      if worksheet
        (2..worksheet.num_rows).each do |row|
          on_off = worksheet[row, 1]&.strip      # ON/OFF 컬럼
          keyword = worksheet[row, 2]&.strip     # 인식 키워드 컬럼
          message = worksheet[row, 4]&.strip     # 답변 출력 컬럼
          
          next unless on_off == 'ON' && keyword&.include?('[출석]') && message && !message.empty?
          
          attendance_messages << message
        end
      end
      
      base_message = if attendance_messages.empty?
        "새로운 하루가 시작되었습니다. 학문에 대한 열정으로 하루를 시작하시길 바랍니다."
      else
        attendance_messages.sample
      end
      
      full_message = <<~MESSAGE
        #{weather_info}
        
        지금부터 출석을 시작합니다.

        #{base_message}
        
        출석 확인을 위해 [출석]을 멘션해 주시기 바랍니다. (오후 10시까지)
        출석 확인 시: 2갈레온 및 기숙사 1점이 지급됩니다.
        
        과제 제출을 원하시는 분은 [과제] 명령어와 함께 교수를 태그해 주시기 바랍니다.
        과제 제출 시: 5갈레온 및 기숙사 3점이 지급됩니다.
      MESSAGE
      
      full_message
      
    rescue => e
      puts "출석 메시지 로드 오류: #{e.message}"
      "오늘 날씨는 추운 겨울이군요. 따뜻하게 입고 다니세요. 지금부터 출석을 시작합니다. [출석]을 멘션해 주시기 바랍니다."
    end
  end

  # 날씨 정보 생성 (겨울 세계관)
  def self.generate_weather_info
    weathers = [
      { condition: "맑은 겨울", temp: "#{rand(-10..5)}°C", advice: "따뜻하게 입고 다니세요" },
      { condition: "눈보라", temp: "#{rand(-15..0)}°C", advice: "외출 시 각별히 주의하세요" },
      { condition: "흐린 겨울", temp: "#{rand(-8..3)}°C", advice: "실내 활동을 권합니다" },
      { condition: "서리", temp: "#{rand(-12..-2)}°C", advice: "발밑을 조심하세요" },
      { condition: "안개 낀 겨울", temp: "#{rand(-5..2)}°C", advice: "시야 확보에 주의하세요" },
      { condition: "강풍을 동반한 겨울", temp: "#{rand(-18..-3)}°C", advice: "외투를 단단히 여미고 다니세요" },
      { condition: "진눈깨비", temp: "#{rand(-2..3)}°C", advice: "미끄러움을 조심하세요" }
    ]
    
    today_weather = weathers.sample
    
    "오늘 날씨는 #{today_weather[:condition]}이군요. #{today_weather[:advice]}."
  end

  # 출석체크 처리
  def self.handle_attendance(mention, acct, display_name)
    # 시간 체크 (9시-22시)
    now = Time.now
    korea_time = now.getlocal("+09:00")
    hour = korea_time.hour
    
    if hour < 9 || hour >= 22
      time_msg = if hour < 9
        "아직 출석 확인 시간이 아닙니다. 오전 9시부터 출석을 받고 있으니 그때 다시 찾아주시기 바랍니다."
      else
        "출석 시간이 마감되었습니다. 내일 오전 9시에 다시 뵙겠습니다. 편안한 밤 되시길 바랍니다."
      end
      
      MastodonClient.reply(mention, time_msg)
      return
    end
    
    # 사용자 확인 (상점봇 사용자 시트에서)
    user_info = get_user_from_shop(acct)
    unless user_info
      MastodonClient.reply(mention, "#{display_name}님, 학적부에서 귀하의 등록 정보를 확인할 수 없습니다.\n먼저 상점봇에서 [입학/성명]으로 입학 절차를 완료해 주시기 바랍니다.")
      return
    end
    
    # 오늘 이미 출석했는지 확인
    today = korea_time.strftime('%Y-%m-%d')
    if already_attended_today?(user_info, today)
      MastodonClient.reply(mention, "#{display_name}님께서는 금일 이미 출석을 완료하셨습니다. 내일 다시 뵙겠습니다.")
      return
    end
    
    # 출석 처리
    success = process_attendance(acct, user_info, today)
    
    if success
      # 랜덤 응답 가져오기
      response_message = get_attendance_response(display_name)
      
      MastodonClient.reply(mention, response_message)
    else
      MastodonClient.reply(mention, "출석 처리 중 문제가 발생하였습니다. 다시 한 번 시도해 주시기 바랍니다.")
    end
  end

  # 과제 제출 처리 (교수님 태그 확인)
  def self.handle_assignment(mention, acct, display_name)
    # 시간 체크 (9시-22시)
    now = Time.now
    korea_time = now.getlocal("+09:00")
    hour = korea_time.hour
    
    if hour < 9 || hour >= 22
      time_msg = if hour < 9
        "아직 과제 제출 시간이 아닙니다. 오전 9시부터 과제를 접수하고 있으니 그때 다시 제출해 주시기 바랍니다."
      else
        "과제 제출 시간이 마감되었습니다. 내일 오전 9시에 다시 제출해 주시기 바랍니다. 편안한 밤 되시길 바랍니다."
      end
      
      MastodonClient.reply(mention, time_msg)
      return
    end
    
    # 교수님 태그 확인
    original_content = mention.status.content
    unless original_content.include?('@') && (original_content.include?('교수') || original_content.include?('professor'))
      MastodonClient.reply(mention, "과제 제출 시에는 담당 교수를 반드시 태그해 주시기 바랍니다.\n올바른 형식: [과제] @교수님 과제를 제출합니다.")
      return
    end
    
    # 사용자 확인
    user_info = get_user_from_shop(acct)
    unless user_info
      MastodonClient.reply(mention, "#{display_name}님, 학적부에서 귀하의 등록 정보를 확인할 수 없습니다.\n먼저 [입학/성명]으로 입학 절차를 완료해 주시기 바랍니다.")
      return
    end
    
    # 오늘 이미 과제 제출했는지 확인
    today = korea_time.strftime('%Y-%m-%d')
    if already_submitted_assignment_today?(user_info, today)
      MastodonClient.reply(mention, "#{display_name}님께서는 금일 이미 과제를 제출하셨습니다. 내일 다른 과제로 뵙겠습니다. 📝")
      return
    end
    
    # 과제 제출 처리
    success = process_assignment(acct, user_info, today)
    
    if success
      # 랜덤 응답 가져오기
      response_message = get_assignment_response(display_name)
      
      MastodonClient.reply(mention, response_message)
    else
      MastodonClient.reply(mention, "과제 제출 처리 중 문제가 발생하였습니다. 다시 한 번 시도해 주시기 바랍니다.")
    end
  end

  # 신규 유저 입학 처리 (상점봇에서 이관)
  def self.handle_enrollment(mention, acct, display_name, new_name)
    new_name = new_name.strip
    
    # 이미 등록된 사용자인지 확인
    existing_user = get_user_from_shop(acct)
    if existing_user
      current_name = existing_user['username']
      MastodonClient.reply(mention, "#{display_name}님께서는 이미 '#{current_name}' 성명으로 등록되어 계십니다.")
      return
    end

    # 신규 유저 데이터
    user_data = {
      'username' => new_name,
      'galleons' => 20,  
      'items' => {},
      'notes' => "#{Date.today} 입학",
      'house' => '',
      'last_attendance' => '',
      'last_assignment' => ''
    }
    
    # 구글 시트에 직접 추가
    add_new_user(acct, user_data)

    welcome_message = "#{new_name}님 호그와트 입학생임을 확인했습니다. 열차에 탑승해주세요."
    
    MastodonClient.reply(mention, welcome_message)
  end

  # 새 사용자를 시트에 추가
  def self.add_new_user(acct, user_data)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return unless worksheet
      
      # 헤더 확인 및 추가 (새로운 헤더 구조)
      headers = [
        'ID', '유저명', '갈레온', '소지품', '비고', '기숙사', '마지막출석일', '마지막과제일', '마지막베팅일'
      ]
      
      headers.each_with_index do |header, index|
        col = index + 1
        if worksheet[1, col].nil? || worksheet[1, col].strip.empty?
          worksheet[1, col] = header
        end
      end
      
      # 마지막 행에 새 사용자 추가
      new_row = worksheet.num_rows + 1
      items_string = format_items(user_data['items'])
      
      worksheet[new_row, 1] = acct                             # ID
      worksheet[new_row, 2] = user_data['username']            # 유저명
      worksheet[new_row, 3] = user_data['galleons']            # 갈레온
      worksheet[new_row, 4] = items_string                     # 소지품
      worksheet[new_row, 5] = user_data['notes']               # 비고
      worksheet[new_row, 6] = user_data['house'] || ''         # 기숙사
      worksheet[new_row, 7] = user_data['last_attendance'] || '' # 마지막출석일
      worksheet[new_row, 8] = user_data['last_assignment'] || '' # 마지막과제일
      worksheet[new_row, 9] = ''                               # 마지막베팅일
      
      worksheet.save
      puts "✅ 신규 사용자 추가됨: #{user_data['username']}"
      
    rescue => e
      puts "신규 사용자 추가 오류: #{e.message}"
    end
  end

  # 아이템 딕셔너리를 문자열로 변환 (상점봇과 공유)
  def self.format_items(items_hash)
    return '' if items_hash.empty?
    
    items_hash.map { |name, count| "#{name}x#{count}" }.join(',')
  end

  # 상점봇 사용자 정보 가져오기
  def self.get_user_from_shop(acct)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return nil unless worksheet
      
      (2..worksheet.num_rows).each do |row|
        if worksheet[row, 1]&.strip == acct  # ID 컬럼
          return {
            'username' => worksheet[row, 2]&.strip,      # 유저명
            'galleons' => worksheet[row, 3]&.to_i || 0,  # 갈레온
            'items' => worksheet[row, 4]&.strip || '',   # 소지품
            'notes' => worksheet[row, 5]&.strip || '',   # 비고
            'house' => worksheet[row, 6]&.strip || '',   # 기숙사
            'last_attendance' => worksheet[row, 7]&.strip || '', # 마지막출석일
            'last_assignment' => worksheet[row, 8]&.strip || ''  # 마지막과제일
          }
        end
      end
      
      nil
    rescue => e
      puts "사용자 정보 조회 오류: #{e.message}"
      nil
    end
  end

  # 오늘 출석 여부 확인 (사용자 시트의 마지막출석일 확인)
  def self.already_attended_today?(user_info, today)
    return false unless user_info['last_attendance']
    user_info['last_attendance'] == today
  end

  # 오늘 과제 제출 여부 확인
  def self.already_submitted_assignment_today?(user_info, today)
    return false unless user_info['last_assignment']
    user_info['last_assignment'] == today
  end

  # 출석 처리 (갈레온 지급 + 기숙사 점수)
  def self.process_attendance(acct, user_info, today)
    begin
      # 1. 갈레온 지급 (상점봇 사용자 시트 업데이트)
      update_user_galleons(acct, user_info['galleons'] + 2)
      
      # 2. 마지막 출석일 업데이트
      update_last_attendance(acct, today)
      
      # 3. 기숙사 점수 추가 (기숙사가 배정된 경우만)
      if user_info['house'] && !user_info['house'].empty?
        add_house_points(user_info['house'], 1, "#{user_info['username']} 출석")
      end
      
      true
    rescue => e
      puts "출석 처리 오류: #{e.message}"
      false
    end
  end

  # 과제 제출 처리 (갈레온 지급 + 기숙사 점수)
  def self.process_assignment(acct, user_info, today)
    begin
      # 1. 갈레온 지급 (5갈레온)
      update_user_galleons(acct, user_info['galleons'] + 5)
      
      # 2. 마지막 과제 제출일 업데이트
      update_last_assignment(acct, today)
      
      # 3. 기숙사 점수 추가 (3점)
      if user_info['house'] && !user_info['house'].empty?
        add_house_points(user_info['house'], 3, "#{user_info['username']} 과제제출")
      end
      
      true
    rescue => e
      puts "과제 제출 처리 오류: #{e.message}"
      false
    end
  end

  # 사용자 갈레온 업데이트
  def self.update_user_galleons(acct, new_galleons)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet
    
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct  # ID 컬럼
        worksheet[row, 3] = new_galleons   # 갈레온 컬럼
        worksheet.save
        puts "✅ #{acct} 갈레온 업데이트: #{new_galleons}G"
        break
      end
    end
  end

  # 마지막 출석일 업데이트
  def self.update_last_attendance(acct, date)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet
    
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct  # ID 컬럼
        worksheet[row, 7] = date           # 마지막출석일 컬럼
        worksheet.save
        puts "✅ #{acct} 출석일 업데이트: #{date}"
        break
      end
    end
  end

  # 마지막 과제 제출일 업데이트
  def self.update_last_assignment(acct, date)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet
    
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct  # ID 컬럼
        worksheet[row, 8] = date           # 마지막과제일 컬럼
        worksheet.save
        puts "✅ #{acct} 과제 제출일 업데이트: #{date}"
        break
      end
    end
  end

  # 기숙사 점수 추가
  def self.add_house_points(house, points, reason)
    begin
      worksheet = spreadsheet.worksheet_by_title(HOUSES_SHEET)
      
      # 워크시트가 없으면 생성
      unless worksheet
        worksheet = spreadsheet.add_worksheet(HOUSES_SHEET)
        worksheet[1, 1] = '기숙사'
        worksheet[1, 2] = '총점'
        worksheet[1, 3] = '최근업데이트'
        
        # 기본 기숙사 생성
        HOUSES.each_with_index do |house_name, idx|
          worksheet[idx + 2, 1] = house_name
          worksheet[idx + 2, 2] = 0
          worksheet[idx + 2, 3] = ''
        end
        worksheet.save
      end
      
      # 기숙사 점수 업데이트
      (2..worksheet.num_rows).each do |row|
        if worksheet[row, 1]&.strip == house
          current_points = worksheet[row, 2]&.to_i || 0
          new_points = current_points + points
          worksheet[row, 2] = new_points
          worksheet[row, 3] = "#{Time.now.strftime('%m/%d %H:%M')} #{reason}"
          worksheet.save
          puts "✅ #{house} 점수 변경: #{points > 0 ? '+' : ''}#{points}점 (#{reason}) → 총 #{new_points}점"
          return true
        end
      end
      
      puts "❌ 기숙사를 찾을 수 없음: #{house}"
      false
    rescue => e
      puts "기숙사 점수 업데이트 오류: #{e.message}"
      false
    end
  end

  # 출석 응답 메시지 가져오기
  def self.get_attendance_response(display_name)
    begin
      # 현재 시간 확인
      now = Time.now
      korea_time = now.getlocal("+09:00")
      hour = korea_time.hour
      
      worksheet = spreadsheet.worksheet_by_title(RESPONSES_SHEET)
      responses = []
      
      if worksheet
        (2..worksheet.num_rows).each do |row|
          on_off = worksheet[row, 1]&.strip      # ON/OFF 컬럼
          keyword = worksheet[row, 2]&.strip     # 인식 키워드 컬럼
          response = worksheet[row, 4]&.strip    # 답변 출력 컬럼
          
          if on_off == 'ON' && keyword&.include?('[출석]') && response && !response.empty?
            responses << response.gsub(/\{name\}/, display_name)
          end
        end
      end
      
      base_response = if responses.empty?
        "#{display_name}님의 출석을 확인하였습니다."
      else
        responses.sample
      end
      
      # 시간대별 추가 메시지
      time_advice = case hour
      when 9..17
        "오늘도 열심히 학업에 정진하시길 바랍니다."
      when 18..20
        "하루 마무리를 잘 하시고 편안한 저녁 되시길 바랍니다."
      when 21
        "출석 마감이 임박했습니다. 다음번에는 좀 더 일찍 출석해 주시기 바랍니다."
      else
        "늦은 시간까지 수고하셨습니다."
      end
      
      "출석 확인: #{base_response}\n학업에 대한 성실함을 인정하여 갈레온 2개와 기숙사 점수 1점을 지급해 드렸습니다.\n\n#{time_advice}"
      
    rescue => e
      puts "응답 메시지 로드 오류: #{e.message}"
      "출석 확인: #{display_name}님의 출석을 확인하였습니다.\n학업에 대한 성실함을 인정하여 갈레온 2개와 기숙사 점수 1점을 지급해 드렸습니다."
    end
  end

  # 과제 응답 메시지 가져오기
  def self.get_assignment_response(display_name)
    begin
      # 현재 시간 확인
      now = Time.now
      korea_time = now.getlocal("+09:00")
      hour = korea_time.hour
      
      worksheet = spreadsheet.worksheet_by_title(RESPONSES_SHEET)
      responses = []
      
      if worksheet
        (2..worksheet.num_rows).each do |row|
          on_off = worksheet[row, 1]&.strip      # ON/OFF 컬럼
          keyword = worksheet[row, 2]&.strip     # 인식 키워드 컬럼
          response = worksheet[row, 4]&.strip    # 답변 출력 컬럼
          
          if on_off == 'ON' && keyword&.include?('[과제]') && response && !response.empty?
            responses << response.gsub(/\{name\}/, display_name)
          end
        end
      end
      
      base_response = if responses.empty?
        "#{display_name}님의 과제를 검토하였습니다."
      else
        responses.sample
      end
      
      # 시간대별 추가 메시지
      time_advice = case hour
      when 9..17
        "계속해서 성실한 학업 자세를 유지하시길 바랍니다."
      when 18..20
        "하루의 마무리를 훌륭하게 해내셨군요."
      when 21
        "과제 제출 마감이 임박했습니다. 다음번에는 좀 더 일찍 제출해 주시기 바랍니다."
      else
        "늦은 시간까지 과제에 임하시느라 수고하셨습니다."
      end
      
      "과제 확인: #{base_response}\n성실한 학업 태도에 대한 보상으로 갈레온 5개와 기숙사 점수 3점을 지급해 드렸습니다.\n\n#{time_advice}"
      
    rescue => e
      puts "과제 응답 메시지 로드 오류: #{e.message}"
      "과제 확인: #{display_name}님의 과제를 검토하였습니다.\n성실한 학업 태도에 대한 보상으로 갈레온 5개와 기숙사 점수 3점을 지급해 드렸습니다."
    end
  end

  # 기숙사 배정
  def self.handle_assign_house(mention, acct, display_name, student_name, house)
    house = house.strip
    student_name = student_name.strip
    
    unless HOUSES.include?(house)
      MastodonClient.reply(mention, "입력하신 기숙사명이 올바르지 않습니다. 다음 중에서 선택해 주시기 바랍니다: #{HOUSES.join(', ')}")
      return
    end
    
    # 학생 찾기 및 기숙사 배정
    success = assign_student_house(student_name, house)
    
    if success
      MastodonClient.reply(mention, "🏠 #{student_name}님을 #{house}에 정식으로 배정하였습니다.\n#{house}의 새로운 구성원이 되신 것을 축하드립니다.")
    else
      MastodonClient.reply(mention, "#{student_name}님의 학적 정보를 찾을 수 없습니다. 학적부를 다시 한번 확인해 주시기 바랍니다.")
    end
  end

  # 학생 기숙사 배정 처리
  def self.assign_student_house(student_name, house)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return false unless worksheet
      
      # 기숙사 컬럼이 없다면 추가
      if worksheet[1, 6].nil? || worksheet[1, 6].strip.empty?
        worksheet[1, 6] = '기숙사'
        worksheet.save
      end
      
      (2..worksheet.num_rows).each do |row|
        username = worksheet[row, 2]&.strip
        if username == student_name
          worksheet[row, 6] = house
          worksheet.save
          puts "✅ #{student_name} → #{house} 배정 완료"
          return true
        end
      end
      
      false
    rescue => e
      puts "기숙사 배정 오류: #{e.message}"
      false
    end
  end

  # 기숙사 순위 확인
  def self.handle_house_ranking(mention, acct, display_name)
    begin
      worksheet = spreadsheet.worksheet_by_title(HOUSES_SHEET)
      unless worksheet
        MastodonClient.reply(mention, "기숙사 점수 기록을 찾을 수 없습니다.")
        return
      end
      
      houses_data = []
      (2..worksheet.num_rows).each do |row|
        house = worksheet[row, 1]&.strip
        points = worksheet[row, 2]&.to_i || 0
        next unless house && !house.empty?
        
        houses_data << { name: house, points: points }
      end
      
      houses_data.sort! { |a, b| b[:points] <=> a[:points] }
      
      ranking_text = "기숙사 점수 현황\n\n"
      houses_data.each_with_index do |house, idx|
        medal = case idx
                when 0 then "1위"
                when 1 then "2위" 
                when 2 then "3위"
                else "#{idx + 1}위"
                end
        ranking_text += "#{medal} #{house[:name]}: #{house[:points]}점\n"
      end
      
      ranking_text += "\n모든 기숙사 학생들의 노력과 성취를 격려합니다."
      
      MastodonClient.reply(mention, ranking_text)
      
    rescue => e
      puts "기숙사 순위 조회 오류: #{e.message}"
      MastodonClient.reply(mention, "기숙사 순위 조회 중 문제가 발생하였습니다.")
    end
  end

  # 점수 부여
  def self.handle_award_points(mention, acct, display_name, student_name, points, reason)
    student_name = student_name.strip
    reason = reason.strip
    
    # 학생 정보 확인
    student_info = find_student_by_name(student_name)
    unless student_info
      MastodonClient.reply(mention, "#{student_name}님의 학적 정보를 찾을 수 없습니다. 학적부를 확인해 주시기 바랍니다.")
      return
    end
    
    unless student_info['house'] && !student_info['house'].empty?
      MastodonClient.reply(mention, "#{student_name}님은 아직 기숙사가 배정되지 않았습니다. 먼저 기숙사 배정을 완료해 주시기 바랍니다.")
      return
    end
    
    # 점수 부여
    success = add_house_points(student_info['house'], points, "#{student_name} #{reason}")
    
    if success
      MastodonClient.reply(mention, "🏆 #{student_name}님(#{student_info['house']})께 #{points}점을 부여하였습니다.\n사유: #{reason}\n\n훌륭한 성취를 축하드립니다.")
    else
      MastodonClient.reply(mention, "점수 부여 과정에서 문제가 발생하였습니다.")
    end
  end

  # 점수 차감
  def self.handle_deduct_points(mention, acct, display_name, student_name, points, reason)
    student_name = student_name.strip
    reason = reason.strip
    
    # 학생 정보 확인
    student_info = find_student_by_name(student_name)
    unless student_info
      MastodonClient.reply(mention, "#{student_name}님의 학적 정보를 찾을 수 없습니다. 학적부를 확인해 주시기 바랍니다.")
      return
    end
    
    unless student_info['house'] && !student_info['house'].empty?
      MastodonClient.reply(mention, "#{student_name}님은 아직 기숙사가 배정되지 않았습니다. 먼저 기숙사 배정을 완료해 주시기 바랍니다.")
      return
    end
    
    # 점수 차감 (음수로 전달)
    success = add_house_points(student_info['house'], -points, "#{student_name} #{reason}")
    
    if success
      MastodonClient.reply(mention, "⚠️ #{student_name}님(#{student_info['house']})께서 #{points}점을 차감당하셨습니다.\n사유: #{reason}\n\n앞으로 더욱 모범적인 행동을 기대합니다.")
    else
      MastodonClient.reply(mention, "점수 차감 과정에서 문제가 발생하였습니다.")
    end
  end

  # 학생 이름으로 찾기
  def self.find_student_by_name(student_name)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return nil unless worksheet
      
      (2..worksheet.num_rows).each do |row|
        username = worksheet[row, 2]&.strip
        if username == student_name
          return {
            'id' => worksheet[row, 1]&.strip,
            'username' => username,
            'galleons' => worksheet[row, 3]&.to_i || 0,
            'house' => worksheet[row, 6]&.strip || ''
          }
        end
      end
      
      nil
    rescue => e
      puts "학생 검색 오류: #{e.message}"
      nil
    end
  end

  # 학생 현황
  def self.handle_student_status(mention, acct, display_name)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      unless worksheet
        MastodonClient.reply(mention, "학생 데이터를 찾을 수 없습니다.")
        return
      end
      
      students = []
      house_count = {}
      total_galleons = 0
      
      (2..worksheet.num_rows).each do |row|
        username = worksheet[row, 2]&.strip
        galleons = worksheet[row, 3]&.to_i || 0
        house = worksheet[row, 6]&.strip || '미배정'
        
        next unless username && !username.empty?
        
        students << { name: username, galleons: galleons, house: house }
        house_count[house] = (house_count[house] || 0) + 1
        total_galleons += galleons
      end
      
      if students.empty?
        MastodonClient.reply(mention, "현재 등록된 학생이 없습니다.")
        return
      end
      
      status_text = "호그와트 학적 현황\n\n"
      status_text += "총 재학생 수: #{students.size}명\n"
      status_text += "전체 보유 갈레온: #{total_galleons}개\n\n"
      
      status_text += "기숙사별 소속 현황:\n"
      house_count.each do |house, count|
        status_text += "   #{house}: #{count}명\n"
      end
      
      status_text += "\n모든 학생들의 학업 정진을 응원합니다."
      
      MastodonClient.reply(mention, status_text)
      
    rescue => e
      puts "학생 현황 조회 오류: #{e.message}"
      MastodonClient.reply(mention, "학생 현황 조회 중 문제가 발생하였습니다.")
    end
  end

  def self.handle_greeting(mention, acct, display_name)
    greeting_responses = [
      "안녕하십니까, #{display_name}님. 호그와트에서의 학문적 여정이 의미 있고 보람차기를 바랍니다.",
      "#{display_name}님, 학업에 정진하시는 모습이 감명 깊습니다. 언제든 도움이 필요하시면 말씀해 주시기 바랍니다.",
      "#{display_name}님께 인사드립니다. 궁금한 사항이나 학업상 문의가 있으시면 주저 말고 말씀해 주세요."
    ]
    
    MastodonClient.reply(mention, greeting_responses.sample)
  end

  def self.handle_help(mention, acct, display_name)
    help_text = <<~HELP
      호그와트 교수봇 학사 업무 안내

      출석 및 과제 관리:
      [출석] - 일일 출석 확인 (09:00-22:00) → 갈레온 2개 + 기숙사 점수 1점
      [과제] - 과제 제출 확인 (09:00-22:00) → 갈레온 5개 + 기숙사 점수 3점
      ※ 각각 일일 1회로 제한됩니다.

      점수 관리 시스템:
      [점수부여/학생명/점수/사유] - 기숙사 점수 부여
      [점수차감/학생명/점수/사유] - 기숙사 점수 차감  
      [기숙사순위] - 전체 기숙사 점수 현황

      기숙사 관리:
      [기숙사배정/학생명/기숙사명] - 신입생 기숙사 배정
      [학생현황] - 전교생 학적 및 기숙사 현황

      자동화 시스템:
      • 매일 09:00 - 출석 체크 시작 공지
      • 매일 22:00 - 출석 체크 마감 공지
      • 출석 및 과제 제출 시 자동 보상 지급

      학업과 관련하여 궁금한 사항이 있으시면 언제든 문의해 주시기 바랍니다.
    HELP
    
    MastodonClient.reply(mention, help_text)
  end

  def self.handle_unknown(mention, acct, display_name, text)
    unknown_responses = [
      "#{display_name}님, 입력하신 명령어를 인식할 수 없습니다. '도움말'을 참조해 주시기 바랍니다.",
      "#{display_name}님, 올바른 명령어 형식을 확인하시려면 '도움말'을 입력해 주세요.",
      "#{display_name}님, 명령어 형식을 다시 확인해 주시기 바랍니다. 예시: [출석], [기숙사순위] 등"
    ]
    
    MastodonClient.reply(mention, unknown_responses.sample)
  end
end
