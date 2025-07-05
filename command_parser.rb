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
    when /^\[도움말\]$/i, /^도움말$/i
      handle_help(mention, acct, display_name)
    else
      handle_unknown(mention, acct, display_name, text)
    end
  end

  def self.handle_enrollment(mention, acct, display_name, name)
    name = name.strip
    existing = get_user(acct)
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
    MastodonClient.reply(mention, "#{name}님 호그와트 입학을 확인하였습니다. 열차에 탑승해주세요.")
  end

  def self.handle_attendance(mention, acct, display_name)
    now = Time.now.getlocal("+09:00")
    if now.hour < 9 || now.hour >= 22
      msg = now.hour < 9 ? "아직 출석 시간 전입니다. 오전 9시부터 가능합니다." : "출석 마감 시간이 지났습니다. 내일 다시 뵙겠습니다."
      MastodonClient.reply(mention, msg)
      return
    end

    user = get_user(acct)
    unless user
      MastodonClient.reply(mention, "#{display_name}님은 등록되지 않았습니다. [입학/이름] 명령어로 등록해 주세요.")
      return
    end

    today = now.strftime('%Y-%m-%d')
    if user['last_attendance'] == today
      MastodonClient.reply(mention, "#{display_name}님은 이미 출석하셨습니다. 내일 다시 출석해 주세요.")
      return
    end

    update_user_field(acct, 3, user['galleons'] + 2)
    update_user_field(acct, 7, today)

    if user['house'] && !user['house'].empty?
      add_house_points(user['house'], 1, "#{user['username']} 출석")
    end

    MastodonClient.reply(mention, "#{display_name}님, 출석이 확인되었습니다. 갈레온 2개와 기숙사 점수 1점을 드렸습니다.")
  end

  def self.handle_assignment(mention, acct, display_name)
    now = Time.now.getlocal("+09:00")
    if now.hour < 9 || now.hour >= 22
      msg = now.hour < 9 ? "아직 과제 제출 시간 전입니다." : "과제 제출 마감 시간이 지났습니다. 내일 다시 제출해 주세요."
      MastodonClient.reply(mention, msg)
      return
    end

    user = get_user(acct)
    unless user
      MastodonClient.reply(mention, "#{display_name}님은 등록되지 않았습니다. [입학/이름] 명령어로 등록해 주세요.")
      return
    end

    today = now.strftime('%Y-%m-%d')
    if user['last_assignment'] == today
      MastodonClient.reply(mention, "#{display_name}님은 이미 오늘 과제를 제출하셨습니다.")
      return
    end

    update_user_field(acct, 3, user['galleons'] + 5)
    update_user_field(acct, 8, today)

    if user['house'] && !user['house'].empty?
      add_house_points(user['house'], 3, "#{user['username']} 과제 제출")
    end

    MastodonClient.reply(mention, "#{display_name}님, 과제 제출을 확인하였습니다. 갈레온 5개와 기숙사 점수 3점을 드렸습니다.")
  end

  def self.handle_help(mention, acct, display_name)
    help = <<~TEXT
      #{display_name}님, 교수봇 이용 안내입니다:

      ✅ 출석: [출석] — 09:00~22:00, 갈레온 +2, 기숙사 점수 +1
      ✅ 과제: [과제] — 09:00~22:00, 갈레온 +5, 기숙사 점수 +3
      ✅ 입학: [입학/이름] — 신규 등록

      ⚗️ 예시: [입학/헤르미온느], [출석], [과제]
    TEXT
    MastodonClient.reply(mention, help)
  end

  def self.handle_unknown(mention, acct, display_name, text)
    MastodonClient.reply(mention, "#{display_name}님, 명령어를 이해하지 못했습니다. '[도움말]'을 입력해 주세요.")
  end

  def self.get_user(acct)
    ws = spreadsheet.worksheet_by_title(USERS_SHEET)
    (2..ws.num_rows).each do |row|
      return {
        'username' => ws[row, 2].strip,
        'galleons' => ws[row, 3].to_i,
        'items' => ws[row, 4],
        'notes' => ws[row, 5],
        'house' => ws[row, 6],
        'last_attendance' => ws[row, 7],
        'last_assignment' => ws[row, 8]
      } if ws[row, 1].strip == acct
    end
    nil
  end

  def self.add_new_user(acct, user)
    ws = spreadsheet.worksheet_by_title(USERS_SHEET)
    row = ws.num_rows + 1
    ws[row, 1] = acct
    ws[row, 2] = user['username']
    ws[row, 3] = user['galleons']
    ws[row, 4] = ''
    ws[row, 5] = user['notes']
    ws[row, 6] = user['house']
    ws[row, 7] = user['last_attendance']
    ws[row, 8] = user['last_assignment']
    ws[row, 9] = ''
    ws.save
  end

  def self.update_user_field(acct, column, value)
    ws = spreadsheet.worksheet_by_title(USERS_SHEET)
    (2..ws.num_rows).each do |row|
      if ws[row, 1].strip == acct
        ws[row, column] = value
        ws.save
        break
      end
    end
  end

  def self.add_house_points(house, points, reason)
    ws = spreadsheet.worksheet_by_title(HOUSES_SHEET)
    (2..ws.num_rows).each do |row|
      if ws[row, 1].strip == house
        current = ws[row, 2].to_i
        ws[row, 2] = current + points
        ws[row, 3] = Time.now.getlocal("+09:00").strftime('%Y-%m-%d %H:%M')
        ws.save
        puts "[기숙사점수] #{house} +#{points}점 (사유: #{reason})"
        break
      end
    end
  end

  def self.spreadsheet
    @spreadsheet ||= google_client.spreadsheet_by_key(ENV['GOOGLE_SHEET_ID'])
  end

  def self.google_client
    @google_client ||= begin
      keyfile = ENV['GOOGLE_CREDENTIALS_PATH']
      raise "인증 파일 누락: #{keyfile}" unless File.exist?(keyfile)
      GoogleDrive::Session.from_service_account_key(keyfile)
    end
  end
end
