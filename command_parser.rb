# professor_command_parser.rb
require_relative 'mastodon_client'
require 'google_drive'
require 'time'
require 'json'

module ProfessorParser
  USERS_SHEET = '사용자'
  PROFESSOR_SHEET = '교수'
  HOUSE_SHEET = '기숙사'

  def self.parse(client, sheet, mention)
    content = mention.status.content.gsub(/<[^>]*>/, '')
    sender = mention.account.acct
    text = content.strip

    puts "[교수봇] 처리 중인 멘션: #{text}"

    session = GoogleDrive::Session.from_config(ENV['GOOGLE_CREDENTIALS_PATH'])
    ws_users = sheet.worksheet_by_title(USERS_SHEET)
    ws_prof = sheet.worksheet_by_title(PROFESSOR_SHEET)
    ws_house = sheet.worksheet_by_title(HOUSE_SHEET)

    return unless professor_bot_active?(ws_prof)

    case text
    when /\[입학\/(.+?)\]/
      name = $1.strip
      handle_register(client, ws_users, sender, name)

    when /\[출석\]/
      handle_attendance(client, ws_users, ws_house, sender)

    when /\[과제\]/
      handle_assignment(client, ws_users, ws_house, sender)
    end
  end

  def self.professor_bot_active?(ws)
    (2..ws.num_rows).each do |row|
      return true if ws[row, 1] == '출석기능' && ws[row, 2].strip.downcase == 'on'
    end
    false
  end

  def self.random_weather_and_note
    weather_options = [
      '눈보라', '함박눈', '잔눈', '진눈깨비', '맑지만 매우 추움', '흐림과 눈발', '맑고 따뜻한 겨울 날씨'
    ]
    note_options = [
      '오늘은 장갑을 꼭 끼도록 하세요.',
      '기침하는 학생이 많습니다. 목도리를 챙기세요.',
      '복도 창문이 얼어붙었습니다. 조심히 다니세요.',
      '기숙사 방 온도를 조절하세요.',
      '따뜻한 음료를 마시면서 수업에 집중합시다.'
    ]
    [weather_options.sample, note_options.sample]
  end

  def self.handle_register(client, ws, id, name)
    row = find_user_row(ws, id)
    if row
      client.reply(id, "#{name}님은 이미 입학하셨습니다.")
    else
      ws.insert_rows(ws.num_rows + 1, [[id, name, 20, '', "#{Time.now.strftime('%Y-%m-%d')} 입학"]])
      ws.save
      client.reply(id, "#{name}님, 입학을 확인했습니다, 열차에 탑승해주세요.")
    end
  end

  def self.handle_attendance(client, ws, ws_house, id)
    row = find_user_row(ws, id)
    unless row
      client.reply(id, "먼저 [입학/이름]으로 등록을 해주세요.")
      return
    end

    now = Time.now
    if now.hour >= 22
      client.reply(id, "출석은 밤 10시 이전에만 가능합니다. 내일 아침에 다시 와주세요.")
      return
    end

    last_date = row[8]&.strip
    today = now.strftime('%Y-%m-%d')

    if last_date == today
      client.reply(id, "오늘은 이미 출석하셨어요. 내일 또 뵙겠습니다.")
      return
    end

    galleon = row[2].to_i + 2
    row[2] = galleon
    row[8] = today
    ws.save

    house_name = row[6]&.strip
    update_house_score(ws_house, house_name, 1) if house_name && !house_name.empty?

    weather, note = random_weather_and_note
    client.reply(id, "오늘 날씨는 '#{weather}'입니다. #{note} \n출석 확인했습니다. 2갈레온과 기숙사 점수 1점을 드립니다.")
  end

  def self.handle_assignment(client, ws, ws_house, id)
    row = find_user_row(ws, id)
    unless row
      client.reply(id, "먼저 [입학/이름]으로 등록을 해주세요.")
      return
    end

    galleon = row[2].to_i + 5
    row[2] = galleon
    ws.save

    house_name = row[6]&.strip
    update_house_score(ws_house, house_name, 3) if house_name && !house_name.empty?

    client.reply(id, "과제 제출 확인했습니다. 5갈레온과 기숙사 점수 3점을 드렸습니다. 고생 많으셨어요.")
  end

  def self.update_house_score(ws, house_name, point)
    (2..ws.num_rows).each do |row|
      if ws[row, 1] == house_name
        ws[row, 2] = ws[row, 2].to_i + point
        ws.save
        break
      end
    end
  end

  def self.find_user_row(ws, id)
    (2..ws.num_rows).each do |row|
      return ws.rows[row - 1] if ws[row, 1] == id
    end
    nil
  end
end
