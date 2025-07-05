# command_parser.rb
require_relative 'mastodon_client'
require 'google_drive'
require 'json'
require 'time'

module CommandParser
  USERS_SHEET = '사용자'
  HOUSES_SHEET = '기숙사점수'
  HOUSES = ['그리핀도르', '슬리데린', '레번클로', '후플푸프']

  def self.handle(mention)
    text = mention.status.content.gsub(/<[^>]*>/, '').strip
    text.gsub!(/^@\w+\s*/, '')  # 맨 앞 @교수님 제거
    acct = mention.account.acct
    display_name = mention.account.display_name || acct
    puts "처리 중인 멘션: #{text}"

    case text
    when /^\[입학\/(.+)\]$/i
      handle_enrollment(mention, acct, display_name, $1)
    when /^\[출석\]$/i
      handle_attendance(mention, acct, display_name)
    when /^\[과제\]$/i
      handle_assignment(mention, acct, display_name)
    else
      handle_unknown(mention, acct, display_name, text)
    end
  end

  def self.google_client
    @google_client ||= begin
      key = ENV['GOOGLE_CREDENTIALS_PATH']
      raise "인증 파일 없음: #{key}" unless File.exist?(key)
      GoogleDrive::Session.from_service_account_key(key)
    end
  end

  def self.spreadsheet
    @spreadsheet ||= google_client.spreadsheet_by_key(ENV['GOOGLE_SHEET_ID'])
  end

  def self.get_user(acct)
    sheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    (2..sheet.num_rows).each do |row|
      return {
        'username' => sheet[row, 2],
        'galleons' => sheet[row, 3].to_i,
        'house' => sheet[row, 6],
        'last_attendance' => sheet[row, 7],
        'last_assignment' => sheet[row, 8]
      } if sheet[row, 1].strip == acct
    end
    nil
  end

  def self.add_new_user(acct, name)
    sheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    new_row = sheet.num_rows + 1
    sheet[new_row, 1] = acct
    sheet[new_row, 2] = name
    sheet[new_row, 3] = 20
    sheet[new_row, 4] = ''
    sheet[new_row, 5] = "#{Date.today} 입학"
    sheet[new_row, 6] = ''
    sheet[new_row, 7] = ''
    sheet[new_row, 8] = ''
    sheet[new_row, 9] = ''
    sheet.save
  end

  def self.handle_enrollment(mention, acct, display_name, name)
    user = get_user(acct)
    if user
      MastodonClient.reply(mention, "#{display_name}님은 이미 #{user['username']} 이름으로 등록되어 있습니다.")
      return
    end
    add_new_user(acct, name.strip)
    MastodonClient.reply(mention, "#{name.strip}님 호그와트 입학을 확인하였습니다. 열차에 탑승해주세요.")
  end

  def self.handle_attendance(mention, acct, display_name)
    now = Time.now.getlocal("+09:00")
    today = now.strftime('%Y-%m-%d')
    hour = now.hour

    return MastodonClient.reply(mention, "출석은 오전 9시부터 오후 10시까지만 가능합니다.") unless (9...22).include?(hour)

    user = get_user(acct)
    return MastodonClient.reply(mention, "#{display_name}님, 등록 정보가 없습니다. [입학/이름] 명령어를 사용해 주세요.") unless user

    if user['last_attendance'] == today
      MastodonClient.reply(mention, "#{display_name}님은 이미 오늘 출석하셨습니다.")
      return
    end

    update_user_field(acct, 3, user['galleons'] + 2)
    update_user_field(acct, 7, today)
    add_house_points(user['house'], 1, "#{user['username']} 출석") if user['house'] && !user['house'].empty?

    MastodonClient.reply(mention, "#{display_name}님, 출석이 확인되었습니다. 갈레온 2개와 기숙사 점수 1점을 지급했습니다.")
  end

  def self.handle_assignment(mention, acct, display_name)
    now = Time.now.getlocal("+09:00")
    today = now.strftime('%Y-%m-%d')
    hour = now.hour

    return MastodonClient.reply(mention, "과제는 오전 9시부터 오후 10시까지만 제출할 수 있습니다.") unless (9...22).include?(hour)

    user = get_user(acct)
    return MastodonClient.reply(mention, "#{display_name}님, 등록 정보가 없습니다. [입학/이름] 명령어를 사용해 주세요.") unless user

    if user['last_assignment'] == today
      MastodonClient.reply(mention, "#{display_name}님은 이미 오늘 과제를 제출하셨습니다.")
      return
    end

    update_user_field(acct, 3, user['galleons'] + 5)
    update_user_field(acct, 8, today)
    add_house_points(user['house'], 3, "#{user['username']} 과제") if user['house'] && !user['house'].empty?

    MastodonClient.reply(mention, "#{display_name}님, 과제 제출이 확인되었습니다. 갈레온 5개와 기숙사 점수 3점을 지급했습니다.")
  end

  def self.update_user_field(acct, column, value)
    sheet = spreadsheet.worksheet_by_title(USERS_SHEET)
    (2..sheet.num_rows).each do |row|
      if sheet[row, 1].strip == acct
        sheet[row, column] = value
        sheet.save
        break
      end
    end
  end

  def self.add_house_points(house, points, reason)
    return unless HOUSES.include?(house)

    sheet = spreadsheet.worksheet_by_title(HOUSES_SHEET)
    (2..sheet.num_rows).each do |row|
      if sheet[row, 1] == house
        current = sheet[row, 2].to_i
        sheet[row, 2] = current + points
        sheet[row, 3] = "#{Time.now.strftime('%Y-%m-%d %H:%M')} - #{reason}"
        sheet.save
        break
      end
    end
  end

  def self.handle_unknown(mention, acct, display_name, text)
    MastodonClient.reply(mention, "#{display_name}님, 명령어를 인식하지 못했습니다. [출석], [과제], [입학/이름] 등의 명령어를 사용해 보세요.")
  end
end
