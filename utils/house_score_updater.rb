# /root/mastodon_bots/professor_bot/utils/house_score_updater.rb
# ============================================
# 기숙사별 점수 자동 갱신 모듈 (사용자 시트 → 기숙사 시트)
# ============================================

module HouseScoreUpdater
  module_function

  def update_house_scores(sheet_manager)
    puts "[HOUSE] 기숙사별 점수 갱신 시작"

    # 1️⃣ 사용자 시트 읽기
    users = sheet_manager.read("사용자", "A:Z")
    if users.nil? || users.empty?
      puts "[ERROR] 사용자 시트를 불러오지 못했습니다."
      return
    end

    headers = users[0]
    house_idx = headers.index("기숙사")
    score_idx = headers.index("기숙사점수")

    if house_idx.nil? || score_idx.nil?
      puts "[ERROR] '기숙사' 또는 '기숙사점수' 열을 찾을 수 없습니다."
      puts "[DEBUG] header=#{headers.inspect}"
      return
    end

    # 2️⃣ 기숙사별 합계 계산
    house_scores = Hash.new(0)
    users[1..].each do |row|
      next if row.nil? || row.empty?
      house = row[house_idx].to_s.strip
      score = (row[score_idx] || 0).to_i
      next if house.empty?
      house_scores[house] += score
    end

    puts "[HOUSE] 계산된 합계: #{house_scores.inspect}"

    # 3️⃣ 기숙사 시트 읽기
    houses_sheet = sheet_manager.read("기숙사", "A:B")
    if houses_sheet.nil? || houses_sheet.empty?
      puts "[ERROR] 기숙사 시트를 불러오지 못했습니다."
      return
    end

    # 4️⃣ 각 기숙사 점수 갱신
    houses_sheet.each_with_index do |row, i|
      next if i == 0
      house_name = row[0].to_s.strip
      next if house_name.empty?

      total_score = house_scores[house_name] || 0
      range = "B#{i + 1}"
      sheet_manager.write("기숙사", range, [[total_score]])
      puts "[HOUSE] #{house_name}: #{total_score}점 반영 완료"
    end

    puts "[HOUSE] 기숙사 점수 갱신 완료"
  rescue => e
    puts "[에러] 기숙사 점수 갱신 중 오류: #{e.message}"
    puts e.backtrace.first(5)
  end
end
