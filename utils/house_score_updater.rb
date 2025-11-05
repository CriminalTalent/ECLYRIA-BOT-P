# /root/mastodon_bots/professor_bot/utils/house_score_updater.rb
# ============================================
# 기숙사별 점수 자동 갱신 모듈
# ============================================

module HouseScoreUpdater
  # 기숙사별 점수를 자동으로 합산하여 "기숙사" 탭에 반영한다.
  def update_house_scores(sheet_manager)
    puts "[DEBUG] 기숙사별 점수 갱신 시작"

    # 1️⃣ 사용자 탭 전체 데이터 읽기
    users = sheet_manager.read_values("사용자!A:I")
    if users.nil? || users.empty?
      puts "[ERROR] 사용자 시트 데이터를 불러오지 못했습니다."
      return
    end

    headers = users[0]
    house_idx = headers.index("기숙사")
    score_idx = headers.index("개별 기숙사 점수")

    if house_idx.nil? || score_idx.nil?
      puts "[ERROR] 사용자 시트에 '기숙사' 또는 '개별 기숙사 점수' 열이 없습니다."
      return
    end

    # 2️⃣ 기숙사별 합계 계산
    house_scores = Hash.new(0)
    users[1..].each do |row|
      next if row.nil? || row.empty?
      house = row[house_idx]
      score = (row[score_idx] || 0).to_i
      next if house.nil? || house.strip.empty?
      house_scores[house] += score
    end

    puts "[DEBUG] 계산된 기숙사 점수: #{house_scores.inspect}"

    # 3️⃣ 기숙사 탭 데이터 읽기
    houses_sheet = sheet_manager.read_values("기숙사!A:B")
    if houses_sheet.nil? || houses_sheet.empty?
      puts "[ERROR] 기숙사 시트를 불러오지 못했습니다."
      return
    end

    # 4️⃣ 기숙사별 점수 반영
    houses_sheet.each_with_index do |row, i|
      next if i == 0
      house_name = row[0]
      next if house_name.nil? || house_name.strip.empty?

      total_score = house_scores[house_name] || 0
      range = "기숙사!B#{i + 1}"
      sheet_manager.update_values(range, [[total_score]])
      puts "[DEBUG] #{house_name} → #{total_score}점 반영 완료"
    end

    puts "[DEBUG] 기숙사별 점수 갱신 완료"
  rescue => e
    puts "[에러] 기숙사 점수 갱신 중 오류: #{e.message}"
    puts e.backtrace.first(5)
  end
end
