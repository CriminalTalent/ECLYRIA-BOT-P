# bot/command_parser.rb (교수봇)
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
    when /^\[출석\]$/i, /^출석$/i
      handle_attendance(mention, acct, display_name)
    when /^\[과제\]$/i, /^과제$/i
      handle_assignment(mention, acct, display_name)
    when /^\[점수부여\/(.+)\/(\d+)\/(.+)\]$/i
      handle_award_points(mention, acct, display_name, $1, $2.to_i, $3)
    when /^\[점수차감\/(.+)\/(\d+)\/(.+)\]$/i
      handle_deduct_points(mention, acct, display_name, $1, $2.to_i, $3)
    when /^\[기숙사배정\/(.+)\/(.+)\]$/i
      handle_assign_house(mention, acct, display_name, $1, $2)
    when /^\[기숙사순위\]$/i, /^\[순위\]$/i
      handle_house_ranking(mention, acct, display_name)
    when /^\[학생현황\]$/i
      handle_student_status(mention, acct, display_name)
    when /안녕/i, /교수님/i, /professor/i
      handle_greeting(mention, acct, display_name)
    when /도움말/i, /help/i
      handle_help(mention, acct, display_name)
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

  # 자동 출석 메시지 가져오기 (매일 9시용)
  def self.get_daily_attendance_message
    begin
      worksheet = spreadsheet.worksheet_by_title(RESPONSES_SHEET)
      return "📚 출석체크를 시작합니다! [출석]을 멘션해주세요!" unless worksheet
      
      attendance_messages = []
      
      (2..worksheet.num_rows).each do |row|
        keyword = worksheet[row, 2]&.strip
        message = worksheet[row, 3]&.strip
        
        next unless keyword&.include?('[출석]') && message && !message.empty?
        
        attendance_messages << message
      end
      
      if attendance_messages.empty?
        "📚 출석체크를 시작합니다! [출석]을 멘션해주세요!"
      else
        "📚 #{attendance_messages.sample}\n\n[출석]을 멘션해주세요! ⏰ 오후 10시까지\n📝 [과제] 제출도 가능합니다!"
      end
      
    rescue => e
      puts "출석 메시지 로드 오류: #{e.message}"
      "📚 출석체크를 시작합니다! [출석]을 멘션해주세요!"
    end
  end

  # 출석체크 처리
  def self.handle_attendance(mention, acct, display_name)
    # 시간 체크 (9시-22시)
    now = Time.now
    korea_time = now.getlocal("+09:00")
    hour = korea_time.hour
    
    if hour < 9 || hour >= 22
      time_msg = if hour < 9
        "아직 출석시간이 아닙니다. 오전 9시부터 출석체크가 가능합니다! 🌅"
      else
        "출석시간이 마감되었습니다. 내일 오전 9시에 다시 만나요! 🌙"
      end
      
      MastodonClient.reply(mention, time_msg)
      return
    end
    
    # 사용자 확인 (상점봇 사용자 시트에서)
    user_info = get_user_from_shop(acct)
    unless user_info
      MastodonClient.reply(mention, "#{display_name}님은 호그와트 학적부에서 확인되지 않습니다.\n먼저 상점봇에서 [입학/이름]으로 등록해주세요! 🏰")
      return
    end
    
    # 오늘 이미 출석했는지 확인
    today = korea_time.strftime('%Y-%m-%d')
    if already_attended_today?(user_info, today)
      MastodonClient.reply(mention, "#{display_name}님은 오늘 이미 출석하셨습니다! 내일 다시 만나요! 📚✨")
      return
    end
    
    # 출석 처리
    success = process_attendance(acct, user_info, today)
    
    if success
      # 랜덤 응답 가져오기
      response_message = get_attendance_response(display_name)
      
      MastodonClient.reply(mention, response_message)
    else
      MastodonClient.reply(mention, "죄송합니다. 출석 처리 중 오류가 발생했습니다. 다시 시도해주세요. 📚")
    end
  end

  # 과제 제출 처리
  def self.handle_assignment(mention, acct, display_name)
    # 시간 체크 (9시-22시)
    now = Time.now
    korea_time = now.getlocal("+09:00")
    hour = korea_time.hour
    
    if hour < 9 || hour >= 22
      time_msg = if hour < 9
        "아직 과제 제출 시간이 아닙니다. 오전 9시부터 제출 가능합니다! 📝"
      else
        "과제 제출 시간이 마감되었습니다. 내일 오전 9시에 다시 만나요! 🌙"
      end
      
      MastodonClient.reply(mention, time_msg)
      return
    end
    
    # 사용자 확인
    user_info = get_user_from_shop(acct)
    unless user_info
      MastodonClient.reply(mention, "#{display_name}님은 호그와트 학적부에서 확인되지 않습니다.\n먼저 상점봇에서 [입학/이름]으로 등록해주세요! 🏰")
      return
    end
    
    # 오늘 이미 과제 제출했는지 확인
    today = korea_time.strftime('%Y-%m-%d')
    if already_submitted_assignment_today?(user_info, today)
      MastodonClient.reply(mention, "#{display_name}님은 오늘 이미 과제를 제출하셨습니다! 내일 다른 과제로 만나요! 📝✨")
      return
    end
    
    # 과제 제출 처리
    success = process_assignment(acct, user_info, today)
    
    if success
      # 랜덤 응답 가져오기
      response_message = get_assignment_response(display_name)
      
      MastodonClient.reply(mention, response_message)
    else
      MastodonClient.reply(mention, "죄송합니다. 과제 제출 처리 중 오류가 발생했습니다. 다시 시도해주세요. 📝")
    end
  end

  # 상점봇 사용자 정보 가져오기
  def self.get_user_from_shop(acct)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return nil unless worksheet
      
      (2..worksheet.num_rows).each do |row|
        if worksheet[row, 1]&.strip == acct
          return {
            'username' => worksheet[row, 2]&.strip,
            'galleons' => worksheet[row, 3]&.to_i || 0,
            'items' => worksheet[row, 4]&.strip || '',
            'notes' => worksheet[row, 5]&.strip || '',
            'house' => worksheet[row, 6]&.strip || '',        # 기숙사 정보
            'last_attendance' => worksheet[row, 7]&.strip || '', # 마지막 출석일
            'last_assignment' => worksheet[row, 8]&.strip || ''  # 마지막 과제 제출일
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
      if worksheet[row, 1]&.strip == acct
        worksheet[row, 3] = new_galleons
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
    
    # 헤더 확인 및 추가
    if worksheet[1, 7].nil? || worksheet[1, 7].strip.empty?
      worksheet[1, 7] = '마지막출석일'
    end
    if worksheet[1, 8].nil? || worksheet[1, 8].strip.empty?
      worksheet[1, 8] = '마지막과제일'
    end
    
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct
        worksheet[row, 7] = date
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
    
    # 헤더 확인 및 추가
    if worksheet[1, 7].nil? || worksheet[1, 7].strip.empty?
      worksheet[1, 7] = '마지막출석일'
    end
    if worksheet[1, 8].nil? || worksheet[1, 8].strip.empty?
      worksheet[1, 8] = '마지막과제일'
    end
    
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct
        worksheet[row, 8] = date
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
      worksheet = spreadsheet.worksheet_by_title(RESPONSES_SHEET)
      responses = []
      
      if worksheet
        (2..worksheet.num_rows).each do |row|
          keyword = worksheet[row, 2]&.strip
          response = worksheet[row, 3]&.strip  # C열: 답변 출력
          
          if keyword&.include?('[출석]') && response && !response.empty?
            responses << response.gsub(/\{name\}/, display_name)
          end
        end
      end
      
      base_response = if responses.empty?
        "#{display_name}님 출석 확인되었습니다!"
      else
        responses.sample
      end
      
      "✅ #{base_response}\n💰 갈레온 +2G\n🏆 기숙사 +1점"
      
    rescue => e
      puts "응답 메시지 로드 오류: #{e.message}"
      "✅ #{display_name}님 출석 확인되었습니다!\n💰 갈레온 +2G\n🏆 기숙사 +1점"
    end
  end

  # 과제 응답 메시지 가져오기
  def self.get_assignment_response(display_name)
    begin
      worksheet = spreadsheet.worksheet_by_title(RESPONSES_SHEET)
      responses = []
      
      if worksheet
        (2..worksheet.num_rows).each do |row|
          keyword = worksheet[row, 2]&.strip
          response = worksheet[row, 3]&.strip  # C열: 답변 출력
          
          if keyword&.include?('[과제]') && response && !response.empty?
            responses << response.gsub(/\{name\}/, display_name)
          end
        end
      end
      
      base_response = if responses.empty?
        "#{display_name}님의 과제를 확인했습니다!"
      else
        responses.sample
      end
      
      "📝 #{base_response}\n💰 갈레온 +5G\n🏆 기숙사 +3점"
      
    rescue => e
      puts "과제 응답 메시지 로드 오류: #{e.message}"
      "📝 #{display_name}님의 과제를 확인했습니다!\n💰 갈레온 +5G\n🏆 기숙사 +3점"
    end
  end

  # 기숙사 배정
  def self.handle_assign_house(mention, acct, display_name, student_name, house)
    house = house.strip
    student_name = student_name.strip
    
    unless HOUSES.include?(house)
      MastodonClient.reply(mention, "존재하지 않는 기숙사입니다. 기숙사 목록: #{HOUSES.join(', ')}")
      return
    end
    
    # 학생 찾기 및 기숙사 배정
    success = assign_student_house(student_name, house)
    
    if success
      MastodonClient.reply(mention, "🏠 #{student_name}님이 #{house}에 배정되었습니다!\n환영합니다! ✨")
    else
      MastodonClient.reply(mention, "❌ #{student_name}님을 찾을 수 없습니다. 학적부를 확인해주세요.")
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
        MastodonClient.reply(mention, "기숙사 점수 데이터가 없습니다.")
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
      
      ranking_text = "🏆 기숙사 점수 순위\n\n"
      houses_data.each_with_index do |house, idx|
        medal = case idx
                when 0 then "🥇"
                when 1 then "🥈" 
                when 2 then "🥉"
                else "#{idx + 1}위"
                end
        ranking_text += "#{medal} #{house[:name]}: #{house[:points]}점\n"
      end
      
      MastodonClient.reply(mention, ranking_text)
      
    rescue => e
      puts "기숙사 순위 조회 오류: #{e.message}"
      MastodonClient.reply(mention, "기숙사 순위 조회 중 오류가 발생했습니다.")
    end
  end

  # 점수 부여
  def self.handle_award_points(mention, acct, display_name, student_name, points, reason)
    student_name = student_name.strip
    reason = reason.strip
    
    # 학생 정보 확인
    student_info = find_student_by_name(student_name)
    unless student_info
      MastodonClient.reply(mention, "❌ #{student_name}님을 찾을 수 없습니다. 학적부를 확인해주세요.")
      return
    end
    
    unless student_info['house'] && !student_info['house'].empty?
      MastodonClient.reply(mention, "❌ #{student_name}님은 기숙사가 배정되지 않았습니다. 먼저 기숙사를 배정해주세요.")
      return
    end
    
    # 점수 부여
    success = add_house_points(student_info['house'], points, "#{student_name} #{reason}")
    
    if success
      MastodonClient.reply(mention, "🏆 #{student_name}님(#{student_info['house']})에게 #{points}점을 부여했습니다!\n사유: #{reason}")
    else
      MastodonClient.reply(mention, "❌ 점수 부여 중 오류가 발생했습니다.")
    end
  end

  # 점수 차감
  def self.handle_deduct_points(mention, acct, display_name, student_name, points, reason)
    student_name = student_name.strip
    reason = reason.strip
    
    # 학생 정보 확인
    student_info = find_student_by_name(student_name)
    unless student_info
      MastodonClient.reply(mention, "❌ #{student_name}님을 찾을 수 없습니다. 학적부를 확인해주세요.")
      return
    end
    
    unless student_info['house'] && !student_info['house'].empty?
      MastodonClient.reply(mention, "❌ #{student_name}님은 기숙사가 배정되지 않았습니다. 먼저 기숙사를 배정해주세요.")
      return
    end
    
    # 점수 차감 (음수로 전달)
    success = add_house_points(student_info['house'], -points, "#{student_name} #{reason}")
    
    if success
      MastodonClient.reply(mention, "⚠️ #{student_name}님(#{student_info['house']})에게서 #{points}점을 차감했습니다.\n사유: #{reason}")
    else
      MastodonClient.reply(mention, "❌ 점수 차감 중 오류가 발생했습니다.")
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
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      unless worksheet
        MastodonClient.reply(mention, "학생 데이터가 없습니다.")
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
        MastodonClient.reply(mention, "등록된 학생이 없습니다.")
        return
      end
      
      status_text = "👥 호그와트 학생 현황\n\n"
      status_text += "📊 총 학생수: #{students.size}명\n"
      status_text += "💰 총 갈레온: #{total_galleons}G\n\n"
      
      status_text += "🏠 기숙사별 현황:\n"
      house_count.each do |house, count|
        status_text += "   #{house}: #{count}명\n"
      end
      
      MastodonClient.reply(mention, status_text)
      
    rescue => e
      puts "학생 현황 조회 오류: #{e.message}"
      MastodonClient.reply(mention, "학생 현황 조회 중 오류가 발생했습니다.")
    end
  end

  # 학생 현황
  def self.handle_student_status(mention, acct, display_name)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      unless worksheet
        MastodonClient.reply(mention, "학생 데이터가 없습니다.")
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
        MastodonClient.reply(mention, "등록된 학생이 없습니다.")
        return
      end
      
      status_text = "👥 호그와트 학생 현황\n\n"
      status_text += "📊 총 학생수: #{students.size}명\n"
      status_text += "💰 총 갈레온: #{total_galleons}G\n\n"
      
      status_text += "🏠 기숙사별 현황:\n"
      house_count.each do |house, count|
        status_text += "   #{house}: #{count}명\n"
      end
      
      MastodonClient.reply(mention, status_text)
      
    rescue => e
      puts "학생 현황 조회 오류: #{e.message}"
      MastodonClient.reply(mention, "학생 현황 조회 중 오류가 발생했습니다.")
    end
  end

  # 출석 현황 (제거됨 - 출석기록 워크시트 없음)

  def self.handle_greeting(mention, acct, display_name)
    greeting_responses = [
      "안녕하세요 #{display_name}님! 호그와트에서 즐거운 학교생활을 보내시길 바랍니다. 📚",
      "#{display_name}님, 오늘도 열심히 공부하시는군요! 👩‍🏫",
      "#{display_name}님 안녕하세요! 궁금한 것이 있으면 언제든 물어보세요. ✨"
    ]
    
    MastodonClient.reply(mention, greeting_responses.sample)
  end

  def self.handle_help(mention, acct, display_name)
    help_text = <<~HELP
      🎓 호그와트 교수봇 도움말

      📚 출석 & 과제 시스템:
      [출석] - 출석체크 (09:00-22:00) → 2갈레온 + 1기숙사점수
      [과제] - 과제제출 (09:00-22:00) → 5갈레온 + 3기숙사점수
      ※ 각각 하루 1회만 가능

      🏆 점수 관리:
      [점수부여/학생명/점수/사유] - 점수 부여
      [점수차감/학생명/점수/사유] - 점수 차감  
      [기숙사순위] - 기숙사별 점수 순위

      🏠 기숙사 관리:
      [기숙사배정/학생명/기숙사명] - 기숙사 배정
      [학생현황] - 전체 학생 현황

      ⏰ 자동 기능:
      • 매일 09:00 - 출석체크 시작 알림
      • 매일 22:00 - 출석체크 마감 알림
      • 출석/과제 시 갈레온 및 기숙사 점수 자동 지급
    HELP
    
    MastodonClient.reply(mention, help_text)
  end

  def self.handle_unknown(mention, acct, display_name, text)
    unknown_responses = [
      "#{display_name}님, 알 수 없는 명령어입니다. '도움말'을 확인해보세요! 📚",
      "#{display_name}님, 교수봇 명령어가 궁금하시면 '도움말'을 입력해주세요! 🎓",
      "#{display_name}님, 명령어 형식을 확인해주세요. 예: [출석], [기숙사순위]"
    ]
    
    MastodonClient.reply(mention, unknown_responses.sample)
  end
end
