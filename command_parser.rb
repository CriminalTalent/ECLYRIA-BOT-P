# command_parser.rb (교수봇)
require_relative 'mastodon_client'
require 'google_drive'
require 'json'
require 'time'

module CommandParser
  USERS_SHEET = '사용자'
  RESPONSES_SHEET = '응답'
  HOUSES_SHEET = '기숙사점수'
  HOUSES = ['그리핀도르', '슬리데린', '레번클로', '후플푸프']

  def self.handle(mention)
    text = mention.status.content.gsub(/<[^>]*>/, '').strip
    acct = mention.account.acct
    display_name = mention.account.display_name || acct
    puts "처리 중인 멘션: #{text}"

    case text
    when /^\[입학\/(.+)\]$/i
      handle_enrollment(mention, acct, display_name, $1)
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
    when /^\[기숙사순위\]$/i
      handle_house_ranking(mention, acct, display_name)
    when /^\[도움말\]$/i, /^도움말$/i
      handle_help(mention, acct, display_name)
    else
      handle_unknown(mention, acct, display_name, text)
    end
  end
  private

  def self.google_client
    @google_client ||= begin
      credentials_path = ENV['GOOGLE_CREDENTIALS_PATH']
      raise "구글 인증 파일이 존재하지 않습니다: #{credentials_path}" unless File.exist?(credentials_path)
      GoogleDrive::Session.from_service_account_key(credentials_path)
    end
  end

  def self.spreadsheet
    @spreadsheet ||= begin
      sheet_id = ENV['GOOGLE_SHEET_ID']
      google_client.spreadsheet_by_key(sheet_id)
    end
  end

  def self.handle_enrollment(mention, acct, display_name, new_name)
    new_name = new_name.strip
    existing_user = get_user_from_shop(acct)

    if existing_user
      current_name = existing_user['username']
      MastodonClient.reply(mention, "#{display_name}님께서는 이미 '#{current_name}' 이름으로 등록되어 계십니다.")
      return
    end

    user_data = {
      'username' => new_name,
      'galleons' => 20,
      'items' => {},
      'notes' => "#{Date.today} 입학",
      'house' => '',
      'last_attendance' => '',
      'last_assignment' => ''
    }

    add_new_user(acct, user_data)
    welcome_message = "#{new_name}님, 호그와트 입학을 확인하였습니다. 열차에 탑승해 주세요."
    MastodonClient.reply(mention, welcome_message)
  end

  def self.add_new_user(acct, user_data)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return unless worksheet

      headers = [
        'ID', '유저명', '갈레온', '소지품', '비고',
        '기숙사', '마지막출석일', '마지막과제일', '마지막베팅일'
      ]

      headers.each_with_index do |header, index|
        worksheet[1, index + 1] = header if worksheet[1, index + 1].nil? || worksheet[1, index + 1].strip.empty?
      end

      new_row = worksheet.num_rows + 1
      worksheet[new_row, 1] = acct
      worksheet[new_row, 2] = user_data['username']
      worksheet[new_row, 3] = user_data['galleons']
      worksheet[new_row, 4] = format_items(user_data['items'])
      worksheet[new_row, 5] = user_data['notes']
      worksheet[new_row, 6] = user_data['house']
      worksheet[new_row, 7] = user_data['last_attendance']
      worksheet[new_row, 8] = user_data['last_assignment']
      worksheet[new_row, 9] = ''
      worksheet.save

    rescue => e
      puts "사용자 추가 오류: #{e.message}"
    end
  end

  def self.format_items(items_hash)
    return '' if items_hash.empty?
    items_hash.map { |k, v| "#{k}x#{v}" }.join(',')
  end

  def self.get_user_from_shop(acct)
    begin
      worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
      return nil unless worksheet

      (2..worksheet.num_rows).each do |row|
        if worksheet[row, 1]&.strip == acct
          return {
            'username' => worksheet[row, 2]&.strip,
            'galleons' => worksheet[row, 3]&.to_i,
            'items' => worksheet[row, 4]&.strip,
            'notes' => worksheet[row, 5]&.strip,
            'house' => worksheet[row, 6]&.strip,
            'last_attendance' => worksheet[row, 7]&.strip,
            'last_assignment' => worksheet[row, 8]&.strip
          }
        end
      end
      nil
    rescue => e
      puts "사용자 조회 오류: #{e.message}"
      nil
    end
  end
  def self.handle_attendance(mention, acct, display_name)
    korea_time = Time.now.getlocal("+09:00")
    hour = korea_time.hour

    if hour < 9 || hour >= 22
      message = hour < 9 ?
        "아직 출석 시간 전입니다. 오전 9시부터 출석이 가능합니다." :
        "출석 마감 시간이 지났습니다. 내일 오전 9시에 다시 출석해 주세요."
      MastodonClient.reply(mention, message)
      return
    end

    user_info = get_user_from_shop(acct)
    unless user_info
      MastodonClient.reply(mention, "#{display_name}님, 등록 정보가 없습니다. 먼저 [입학/성명]으로 입학 절차를 완료해 주세요.")
      return
    end

    today = korea_time.strftime('%Y-%m-%d')
    if user_info['last_attendance'] == today
      MastodonClient.reply(mention, "#{display_name}님은 이미 오늘 출석하셨습니다. 내일 다시 출석해 주세요.")
      return
    end

    update_user_galleons(acct, user_info['galleons'] + 2)
    update_last_attendance(acct, today)

    if user_info['house'] && !user_info['house'].empty?
      add_house_points(user_info['house'], 1, "#{user_info['username']} 출석")
    end

    message = "#{display_name}님, 출석이 확인되었습니다.\n갈레온 2개와 기숙사 점수 1점을 드렸습니다.\n오늘 하루도 유익하게 보내시길 바랍니다."
    MastodonClient.reply(mention, message)
  end

  def self.update_user_galleons(acct, new_galleons)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct
        worksheet[row, 3] = new_galleons
        worksheet.save
        break
      end
    end
  end

  def self.update_last_attendance(acct, date)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct
        worksheet[row, 7] = date
        worksheet.save
        break
      end
    end
  end

  def self.handle_assignment(mention, acct, display_name)
    korea_time = Time.now.getlocal("+09:00")
    hour = korea_time.hour

    if hour < 9 || hour >= 22
      msg = hour < 9 ?
        "아직 과제 제출 시간 전입니다. 오전 9시 이후 제출해 주세요." :
        "과제 제출 마감 시간이 지났습니다. 내일 다시 제출해 주세요."
      MastodonClient.reply(mention, msg)
      return
    end

    unless mention.status.content.include?('@')
      MastodonClient.reply(mention, "과제 제출 시 반드시 교수님을 태그해 주세요. 예: [과제] @교수님")
      return
    end

    user_info = get_user_from_shop(acct)
    unless user_info
      MastodonClient.reply(mention, "#{display_name}님, 등록 정보가 없습니다. 먼저 [입학/성명]으로 입학해 주세요.")
      return
    end

    today = korea_time.strftime('%Y-%m-%d')
    if user_info['last_assignment'] == today
      MastodonClient.reply(mention, "#{display_name}님, 이미 오늘 과제를 제출하셨습니다. 내일 다시 뵙겠습니다.")
      return
    end

    update_user_galleons(acct, user_info['galleons'] + 5)
    update_last_assignment(acct, today)

    if user_info['house'] && !user_info['house'].empty?
      add_house_points(user_info['house'], 3, "#{user_info['username']} 과제제출")
    end

    message = "#{display_name}님, 과제 제출이 확인되었습니다.\n갈레온 5개와 기숙사 점수 3점을 드렸습니다.\n오늘도 학업에 최선을 다해주셔서 감사합니다."
    MastodonClient.reply(mention, message)
  end

  def self.update_last_assignment(acct, date)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet
    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct
        worksheet[row, 8] = date
        worksheet.save
        break
      end
    end
  end
  def self.handle_enrollment(mention, acct, display_name, name)
    name = name.strip
    existing = get_user_from_shop(acct)
    if existing
      MastodonClient.reply(mention, "#{display_name}님은 이미 #{existing['username']} 이름으로 등록되어 있습니다.")
      return
    end

    user_data = {
      'username' => name,
      'galleons' => 20,
      'items' => {},
      'notes' => "#{Date.today} 입학",
      'house' => '',
      'last_attendance' => '',
      'last_assignment' => ''
    }

    add_new_user(acct, user_data)

    message = "#{name}님 호그와트 입학을 확인하였습니다. 열차에 탑승해주세요."
    MastodonClient.reply(mention, message)
  end

  def self.add_new_user(acct, user_data)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return unless worksheet

    new_row = worksheet.num_rows + 1
    worksheet[new_row, 1] = acct
    worksheet[new_row, 2] = user_data['username']
    worksheet[new_row, 3] = user_data['galleons']
    worksheet[new_row, 4] = format_items(user_data['items'])
    worksheet[new_row, 5] = user_data['notes']
    worksheet[new_row, 6] = user_data['house']
    worksheet[new_row, 7] = user_data['last_attendance']
    worksheet[new_row, 8] = user_data['last_assignment']
    worksheet[new_row, 9] = ''
    worksheet.save
  end

  def self.format_items(items)
    return '' if items.empty?
    items.map { |k, v| "#{k}x#{v}" }.join(',')
  end

  def self.get_user_from_shop(acct)
    worksheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    return nil unless worksheet

    (2..worksheet.num_rows).each do |row|
      if worksheet[row, 1]&.strip == acct
        return {
          'username' => worksheet[row, 2]&.strip,
          'galleons' => worksheet[row, 3]&.to_i,
          'items' => worksheet[row, 4]&.strip || '',
          'notes' => worksheet[row, 5]&.strip || '',
          'house' => worksheet[row, 6]&.strip || '',
          'last_attendance' => worksheet[row, 7]&.strip || '',
          'last_assignment' => worksheet[row, 8]&.strip || ''
        }
      end
    end

    nil
  end

  def self.handle_greeting(mention, acct, display_name)
    greetings = [
      "#{display_name}님, 반갑습니다. 호그와트에서의 하루가 뜻깊기를 바랍니다.",
      "오늘도 찾아주셨군요, #{display_name}님. 질문이 있다면 언제든지 말씀해 주세요.",
      "#{display_name}님, 이 아침에 다시 뵙게 되어 기쁩니다. 학문적 여정을 응원합니다."
    ]
    MastodonClient.reply(mention, greetings.sample)
  end

  def self.handle_unknown(mention, acct, display_name, text)
    responses = [
      "#{display_name}님, 이해하지 못한 명령입니다. '[출석]', '[과제]' 등의 형식을 참고해 주세요.",
      "#{display_name}님, 올바른 명령어를 다시 입력해 주세요. 예: [출석], [과제]",
      "#{display_name}님, 명령어를 인식하지 못했습니다. '[도움말]'을 입력하시면 자세한 안내를 드릴 수 있습니다."
    ]
    MastodonClient.reply(mention, responses.sample)
  end
  def self.handle_help(mention, acct, display_name)
    help_text = <<~HELP
      #{display_name}님, 교수봇 이용 방법은 아래와 같습니다.

      📌 출석 및 과제
      - [출석] : 매일 09:00 ~ 22:00 출석 체크 → 갈레온 2개, 기숙사 점수 1점 지급
      - [과제] : 교수님을 태그하고 과제 제출 → 갈레온 5개, 기숙사 점수 3점 지급

      📌 기숙사 점수 관리
      - [점수부여/학생명/점수/사유]
      - [점수차감/학생명/점수/사유]
      - [기숙사순위] : 기숙사별 점수 확인

      📌 입학/관리
      - [입학/이름] : 신규 입학생 등록
      - [기숙사배정/이름/기숙사] : 학생의 기숙사 배정

      ⏰ 자동 시스템
      - 매일 오전 9시: 출석 시작 공지
      - 매일 오후 10시: 출석 마감 알림

      추가 문의 사항은 언제든지 멘션해 주세요.
    HELP

    MastodonClient.reply(mention, help_text)
  end

  def self.spreadsheet
    @spreadsheet ||= google_client.spreadsheet_by_key(ENV['GOOGLE_SHEET_ID'])
  end

  def self.google_client
    @google_client ||= begin
      credentials_path = ENV['GOOGLE_CREDENTIALS_PATH']
      raise "인증 파일 누락: #{credentials_path}" unless File.exist?(credentials_path)
      GoogleDrive::Session.from_service_account_key(credentials_path)
    end
  end
end
# 이 파트는 command_parser.rb 파일의 끝부분으로, 모듈 종료입니다.

# 위 코드는 사용자 멘션 기반의 교수봇 명령어를 처리하며,
# Google Sheets와의 연동을 통해 학적 관리 및 보상 시스템을 운영합니다.

# 각 기능은 다음 기준을 따릅니다:
# - 시간 기반 제한 (출석/과제는 09:00~22:00 사이만 허용)
# - 1일 1회 제한
# - 기숙사 점수 및 갈레온 자동 계산 및 저장
# - 온화한 교수님 말투로 응답

# 향후 추가 기능 제안:
# - 베팅 시스템 연동
# - 출석 연속 보너스 기능
# - 과제 난이도별 차등 보상
# - 수업 및 퀴즈 기능 등

# 👨‍🏫 항상 성실한 학생들을 응원합니다.
