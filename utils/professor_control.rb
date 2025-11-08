# /root/mastodon_bots/professor_bot/utils/professor_control.rb
require 'date'

module ProfessorControl
  module_function
  # ⬆️ 다른 파일에서 바로 ProfessorControl.auto_push_enabled? 로 사용 가능

  # --------------------------------------------------
  # 교수 시트에서 특정 기능(출석, 과제, 자동멘트 등) ON/OFF 상태 확인
  # --------------------------------------------------
  def auto_push_enabled?(sheet_manager, feature_name)
    begin
      values = sheet_manager.read("교수!A1:Z2") || []
      return false if values.empty?

      headers = values[0]
      statuses = values[1] || []

      headers.each_with_index do |header, idx|
        next if header.nil?
        next unless header.strip == feature_name

        cell_value = statuses[idx]

        # ✅ 체크박스(true/false) + 문자열(ON/OFF) 모두 허용
        return true  if cell_value == true
        return true  if cell_value.to_s.strip.upcase == "ON"
        return false
      end

      false
    rescue => e
      puts "[에러] auto_push_enabled? 확인 중 오류: #{e.message}"
      false
    end
  end

  # --------------------------------------------------
  # 특정 시간 범위 내인지 확인 (22시 이후 출석 제한 등)
  # - 자정 넘어가는 구간도 처리 가능
  # --------------------------------------------------
  def within_time_range?(start_hour, end_hour)
    now = Time.now.hour

    if start_hour < end_hour
      (start_hour <= now && now < end_hour)
    else
      # 예: (22, 6) → 밤 10시~새벽 6시
      (now >= start_hour || now < end_hour)
    end
  end

  # --------------------------------------------------
  # 공지 / 멘트용 포맷 일관화
  # --------------------------------------------------
  def formatted_announcement(type, message)
    timestamp = Time.now.strftime("%H:%M")
    "[#{type}] #{timestamp} - #{message}"
  end
end
