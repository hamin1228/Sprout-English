class RoleplayScenarioExact {
  final String id;
  final String difficulty;
  final String title;
  final String subtitle;
  final String sceneTitle;
  final String backgroundAsset;

  const RoleplayScenarioExact({
    required this.id,
    required this.difficulty,
    required this.title,
    required this.subtitle,
    required this.sceneTitle,
    required this.backgroundAsset,
  });
}

class RoleplayScenarioCatalogExact {
  static const List<RoleplayScenarioExact> all = [
    RoleplayScenarioExact(
      id: 'beginner_self_intro',
      difficulty: '초급',
      title: '자기소개하기',
      subtitle: '간단한 인사와 소개',
      sceneTitle: 'Self Introduction',
      backgroundAsset: 'assets/roleplay/backgrounds/beginner_self_intro.jpg',
    ),
    RoleplayScenarioExact(
      id: 'beginner_cafe_order',
      difficulty: '초급',
      title: '카페에서 주문하기',
      subtitle: '원하는 메뉴를 주문',
      sceneTitle: 'At a Cafe',
      backgroundAsset: 'assets/roleplay/backgrounds/beginner_cafe_order.jpg',
    ),
    RoleplayScenarioExact(
      id: 'beginner_ask_directions',
      difficulty: '초급',
      title: '길 묻기',
      subtitle: '목적지까지 가는 길 문의',
      sceneTitle: 'Asking for Directions',
      backgroundAsset:
          'assets/roleplay/backgrounds/beginner_ask_directions.jpg',
    ),
    RoleplayScenarioExact(
      id: 'beginner_store_purchase',
      difficulty: '초급',
      title: '가게에서 물건 사기',
      subtitle: '상품에 대해 질문하고 구매',
      sceneTitle: 'Shopping in a Store',
      backgroundAsset:
          'assets/roleplay/backgrounds/beginner_store_purchase.jpg',
    ),
    RoleplayScenarioExact(
      id: 'intermediate_hotel_checkin',
      difficulty: '중급',
      title: '호텔 체크인',
      subtitle: '예약 확인과 요청하기',
      sceneTitle: 'Hotel Check-in',
      backgroundAsset:
          'assets/roleplay/backgrounds/intermediate_hotel_checkin.jpg',
    ),
    RoleplayScenarioExact(
      id: 'intermediate_baggage_issue',
      difficulty: '중급',
      title: '공항 수하물 문제',
      subtitle: '짐 분실과 지연 문의',
      sceneTitle: 'Airport Baggage Desk',
      backgroundAsset:
          'assets/roleplay/backgrounds/intermediate_baggage_issue.jpg',
    ),
    RoleplayScenarioExact(
      id: 'intermediate_doctor_appointment',
      difficulty: '중급',
      title: '병원 예약 문의',
      subtitle: '증상을 설명하고 예약',
      sceneTitle: 'Doctor Appointment',
      backgroundAsset:
          'assets/roleplay/backgrounds/intermediate_doctor_appointment.jpg',
    ),
    RoleplayScenarioExact(
      id: 'intermediate_meeting_schedule',
      difficulty: '중급',
      title: '업무 미팅 잡기',
      subtitle: '시간과 안건 조율',
      sceneTitle: 'Scheduling a Meeting',
      backgroundAsset:
          'assets/roleplay/backgrounds/intermediate_meeting_schedule.jpg',
    ),
    RoleplayScenarioExact(
      id: 'advanced_restaurant_complaint',
      difficulty: '고급',
      title: '식당 컴플레인',
      subtitle: '문제를 설명하고 해결 요청',
      sceneTitle: 'Restaurant Complaint',
      backgroundAsset:
          'assets/roleplay/backgrounds/advanced_restaurant_complaint.jpg',
    ),
    RoleplayScenarioExact(
      id: 'advanced_deadline_negotiation',
      difficulty: '고급',
      title: '마감 일정 협상',
      subtitle: '지연과 대안 제안',
      sceneTitle: 'Deadline Negotiation',
      backgroundAsset:
          'assets/roleplay/backgrounds/advanced_deadline_negotiation.jpg',
    ),
    RoleplayScenarioExact(
      id: 'advanced_lost_passport',
      difficulty: '고급',
      title: '여권 분실 신고',
      subtitle: '긴급 서류 절차 문의',
      sceneTitle: 'Lost Passport Report',
      backgroundAsset: 'assets/roleplay/backgrounds/advanced_lost_passport.jpg',
    ),
    RoleplayScenarioExact(
      id: 'advanced_performance_review',
      difficulty: '고급',
      title: '성과 리뷰 면담',
      subtitle: '성과와 지원 요청 논의',
      sceneTitle: 'Performance Review',
      backgroundAsset:
          'assets/roleplay/backgrounds/advanced_performance_review.jpg',
    ),
  ];

  static List<RoleplayScenarioExact> byDifficulty(String difficulty) {
    return all.where((item) => item.difficulty == difficulty).toList();
  }
}
