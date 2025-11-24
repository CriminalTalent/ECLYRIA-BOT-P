# utils/house_score_updater.rb
# ============================================
# 기숙사별 점수 자동 갱신 모듈 (사용자 시트 → 기숙사 시트)
# ============================================

module HouseScoreUpdater
  module_function

  def update_house_scores(sheet_manager)
    puts "[기숙사] 점수 갱신 시작"

    # 1단계: 사용자 시트 읽기
    users = sheet_manager.read("사용자", "A:Z")
    if users.nil? || users.empty?
      puts "[에러] 사용자 시트를 불러오지 못했습니다."
      return
    end

    headers = users[0]
    house_idx = headers.index("기숙사")
    score_idx = headers.index("개별 기숙사 점수")  # 수정: 정확한 열 이름 사용

    if house_idx.nil? || score_idx.nil?
      puts "[에러] '기숙사' 또는 '개별 기숙사 점수' 열을 찾을 수 없습니다."
      puts "[디버그] headers=#{headers.inspect}"
      return
    end

    puts "[디버그] 기숙사 열 위치: #{house_idx}, 점수 열 위치: #{score_idx}"

    # 2단계: 기숙사별 합계 계산
    house_scores = Hash.new(0)
    processed_count = 0

    users[1..].each do |row|
      next if row.nil? || row.empty?
      
      house = row[house_idx].to_s.strip
      score = (row[score_idx] || 0).to_i
      
      next if house.empty?
      
      house_scores[house] += score
      processed_count += 1
    end

    puts "[기숙사] 처리된 학생 수: #{processed_count}"
    puts "[기숙사] 계산된 합계: #{house_scores.inspect}"

    # 3단계: 기숙사 시트 읽기
    houses_sheet = sheet_manager.read("기숙사", "A:B")
    if houses_sheet.nil? || houses_sheet.empty?
      puts "[에러] 기숙사 시트를 불러오지 못했습니다."
      return
    end

    # 4단계: 각 기숙사 점수 갱신
    updated_count = 0
    houses_sheet.each_with_index do |row, i|
      next if i == 0  # 헤더 스킵
      
      house_name = row[0].to_s.strip
      next if house_name.empty?

      total_score = house_scores[house_name] || 0
      range = "B#{i + 1}"
      
      sheet_manager.write("기숙사", range, [[total_score]])
      puts "[기숙사] #{house_name}: #{total_score}점 반영 완료"
      updated_count += 1
    end

    puts "[기숙사] 점수 갱신 완료 (#{updated_count}개 기숙사)"

  rescue => e
    puts "[에러] 기숙사 점수 갱신 중 오류: #{e.message}"
    puts e.backtrace.first(5)
  end
end
