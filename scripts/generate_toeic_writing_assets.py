from __future__ import annotations

import json
import random
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "toeic_writing_images"
PROMPT_BANK_PATH = ROOT / "server" / "dictionaries" / "toeic_writing_prompts.json"
SEED = 20260321


def _picture_beginner_specs() -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    templates = [
        {
            "slug": "cafe_order",
            "title": "Cafe Counter Scene",
            "sign": "CAFE ORDER",
            "setting": "counter",
            "points": [
                "A customer is standing at the counter.",
                "A worker is serving food or a drink.",
                "A menu board is visible behind the counter.",
            ],
            "answer": "A customer is standing at the counter in a cafe. A worker is serving a drink behind the counter. A menu board is hanging on the wall, so the place looks busy and organized.",
        },
        {
            "slug": "bookstore",
            "title": "Bookstore Browsing",
            "sign": "BOOK SHOP",
            "setting": "meeting",
            "points": [
                "A person is looking at books on a table.",
                "Several books are stacked nearby.",
                "A window or shelf is visible in the room.",
            ],
            "answer": "A person is looking at books in a bookstore. Several books are stacked on the table near the customer. A bright window makes the room look calm and comfortable.",
        },
        {
            "slug": "park_bench",
            "title": "Park Bench Break",
            "sign": "CITY PARK",
            "setting": "park",
            "points": [
                "A person is sitting or standing near a bench.",
                "There is a tree or plant in the park.",
                "The scene looks quiet and relaxed.",
            ],
            "answer": "A person is spending time near a bench in the park. There is a large tree and some green plants in the background. The scene looks quiet and relaxed.",
        },
        {
            "slug": "bus_stop",
            "title": "Bus Stop Wait",
            "sign": "BUS STOP",
            "setting": "waiting",
            "points": [
                "A person is waiting in the seating area.",
                "A clock or sign is visible.",
                "The place looks like a public waiting area.",
            ],
            "answer": "A person is waiting in a public seating area. A clock and a sign are visible on the wall. It looks like a bus stop or a station waiting area.",
        },
        {
            "slug": "grocery_checkout",
            "title": "Grocery Checkout",
            "sign": "CHECKOUT",
            "setting": "counter",
            "points": [
                "A customer is standing in front of a counter.",
                "A bag or small item is visible.",
                "The scene looks like a shop checkout area.",
            ],
            "answer": "A customer is standing in front of a checkout counter. A shopping bag and small items are visible near the counter. The scene looks like a shop where someone is paying for goods.",
        },
        {
            "slug": "classroom",
            "title": "Classroom Question",
            "sign": "CLASSROOM",
            "setting": "meeting",
            "points": [
                "A student is standing near a table or desk.",
                "A laptop or book is visible.",
                "The room looks like a classroom or study space.",
            ],
            "answer": "A student is standing near a desk in a classroom. A laptop and some study materials are visible on the table. The room looks like a quiet study space.",
        },
        {
            "slug": "flower_shop",
            "title": "Flower Shop Visit",
            "sign": "FLOWERS",
            "setting": "counter",
            "points": [
                "A customer is standing near the counter.",
                "Plants or flowers are visible.",
                "The place looks bright and welcoming.",
            ],
            "answer": "A customer is standing near the counter in a flower shop. Plants and flowers are visible around the room. The place looks bright and welcoming.",
        },
        {
            "slug": "library",
            "title": "Library Reading Table",
            "sign": "LIBRARY",
            "setting": "meeting",
            "points": [
                "A person is reading or studying at a table.",
                "Books are visible in the room.",
                "The scene looks quiet and focused.",
            ],
            "answer": "A person is studying at a table in the library. Several books are visible near the desk. The scene looks quiet and focused.",
        },
        {
            "slug": "station_platform",
            "title": "Station Platform",
            "sign": "PLATFORM",
            "setting": "waiting",
            "points": [
                "A traveler is standing with a bag or suitcase.",
                "A sign or clock is visible.",
                "The place looks like a station platform.",
            ],
            "answer": "A traveler is standing with a bag in the station area. A sign and a clock are visible nearby. The place looks like a station platform before departure.",
        },
        {
            "slug": "street_crossing",
            "title": "Street Crossing Scene",
            "sign": "CROSS WALK",
            "setting": "street",
            "points": [
                "A person is walking on the street.",
                "The road markings are visible.",
                "The scene looks active but safe.",
            ],
            "answer": "A person is walking across the street. The road markings are clearly visible in front of the person. The scene looks active but safe.",
        },
    ]
    for index in range(50):
        template = templates[index % len(templates)]
        variant = index // len(templates)
        prompt = {
            "prompt_id": f"picture_beginner_{index + 1:02d}",
            "task_type": "picture",
            "level": "beginner",
            "title": f"{template['title']} {variant + 1}",
            "instructions": "Look at the picture and describe the scene in English. Mention the main people, actions, and objects you notice.",
            "time_limit_sec": 480,
            "recommended_words": 80,
            "required_points": template["points"],
            "image_asset": f"assets/toeic_writing_images/beginner/scene_{index + 1:02d}.jpg",
            "source_text": None,
            "keywords": [],
            "model_answer": template["answer"],
        }
        specs.append(prompt)
    return specs


def _picture_intermediate_specs() -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    templates = [
        {
            "slug": "office_meeting",
            "title": "Office Team Meeting",
            "sign": "TEAM ROOM",
            "setting": "meeting",
            "points": [
                "Several coworkers are sitting or standing around a table.",
                "A laptop or documents are visible on the table.",
                "A presentation board or sign is visible.",
                "The team appears to be discussing work.",
            ],
            "answer": "Several coworkers are gathered around a table in a meeting room. A laptop and some documents are visible in front of them. A presentation board is hanging on the wall. The team appears to be discussing work together.",
        },
        {
            "slug": "service_desk",
            "title": "Customer Service Desk",
            "sign": "HELP DESK",
            "setting": "counter",
            "points": [
                "A customer is speaking to a staff member at the desk.",
                "A computer or monitor is visible.",
                "A bag, paper, or small item is placed nearby.",
                "The scene looks like a service counter.",
            ],
            "answer": "A customer is speaking to a staff member at the service desk. A monitor is visible behind the counter, and some papers are placed nearby. The scene looks like a help desk where someone is asking for assistance.",
        },
        {
            "slug": "shipment_room",
            "title": "Shipment Preparation",
            "sign": "SHIPPING",
            "setting": "meeting",
            "points": [
                "A worker is standing near several boxes.",
                "A table or desk is used for preparation.",
                "A laptop or paper is visible.",
                "The scene looks busy and organized.",
            ],
            "answer": "A worker is standing near several boxes in a preparation area. A desk is being used to organize the shipment. A laptop and some papers are visible on the table. The scene looks busy and organized.",
        },
        {
            "slug": "hotel_checkin",
            "title": "Hotel Check-in Desk",
            "sign": "HOTEL DESK",
            "setting": "counter",
            "points": [
                "A guest is standing at the front desk.",
                "A staff member is helping the guest.",
                "A suitcase or bag is visible.",
                "The place looks like a hotel lobby.",
            ],
            "answer": "A guest is standing at the front desk in a hotel lobby. A staff member is helping the guest from behind the counter. A suitcase is visible beside the traveler. The place looks like a hotel during check-in.",
        },
        {
            "slug": "clinic_reception",
            "title": "Clinic Reception Area",
            "sign": "RECEPTION",
            "setting": "waiting",
            "points": [
                "A visitor is waiting or checking in.",
                "A clock and seating area are visible.",
                "A staff member or another visitor is nearby.",
                "The place looks calm and professional.",
            ],
            "answer": "A visitor is checking in or waiting at a reception area. A clock and several seats are visible in the room. Another person is nearby, so the scene feels calm and professional.",
        },
        {
            "slug": "airport_checkin",
            "title": "Airport Check-in",
            "sign": "CHECK-IN",
            "setting": "waiting",
            "points": [
                "A traveler is standing with a suitcase.",
                "A clock or sign is visible above the area.",
                "Another person is waiting nearby.",
                "The place looks like an airport or terminal.",
            ],
            "answer": "A traveler is standing with a suitcase in a terminal. A check-in sign and a clock are visible above the area. Another person is waiting nearby. The place looks like an airport before departure.",
        },
        {
            "slug": "project_review",
            "title": "Project Review Table",
            "sign": "PROJECT",
            "setting": "meeting",
            "points": [
                "Two or more people are working around a table.",
                "A laptop and papers are visible.",
                "The room looks like an office workspace.",
                "The group appears to be reviewing a plan.",
            ],
            "answer": "Two coworkers are working around a table in an office. A laptop and several papers are visible in front of them. The room looks like a workspace for team meetings. They appear to be reviewing a project plan together.",
        },
        {
            "slug": "conference_booth",
            "title": "Conference Booth Visit",
            "sign": "INFO BOOTH",
            "setting": "counter",
            "points": [
                "A visitor is speaking to a staff member at the booth.",
                "Printed materials or a screen are visible.",
                "The scene looks like an event or conference area.",
                "The interaction appears formal and helpful.",
            ],
            "answer": "A visitor is speaking to a staff member at an information booth. Printed materials and a screen are visible near the counter. The scene looks like an event or conference area. The interaction appears formal and helpful.",
        },
        {
            "slug": "store_restocking",
            "title": "Store Restocking",
            "sign": "STOCK ROOM",
            "setting": "meeting",
            "points": [
                "A worker is organizing boxes or items.",
                "A table or shelf is visible.",
                "Another person is helping or checking the list.",
                "The scene looks like a stock room.",
            ],
            "answer": "A worker is organizing boxes in a stock room. A table is visible beside the boxes, and another person appears to be checking a list. The scene looks like a back room where items are being prepared.",
        },
        {
            "slug": "repair_counter",
            "title": "Repair Counter",
            "sign": "SERVICE",
            "setting": "counter",
            "points": [
                "A customer is speaking to a staff member.",
                "A monitor, paper, or device is visible.",
                "The place looks like a repair or service desk.",
                "The scene suggests a request for help.",
            ],
            "answer": "A customer is speaking to a staff member at a service counter. A monitor and some paperwork are visible behind the desk. The place looks like a repair center where someone is asking for help.",
        },
    ]
    for index in range(50):
        template = templates[index % len(templates)]
        variant = index // len(templates)
        prompt = {
            "prompt_id": f"picture_intermediate_{index + 1:02d}",
            "task_type": "picture",
            "level": "intermediate",
            "title": f"{template['title']} {variant + 1}",
            "instructions": "Look at the picture and describe the scene in English. Cover the main people, actions, and details clearly.",
            "time_limit_sec": 600,
            "recommended_words": 110,
            "required_points": template["points"],
            "image_asset": f"assets/toeic_writing_images/intermediate/scene_{index + 1:02d}.jpg",
            "source_text": None,
            "keywords": [],
            "model_answer": template["answer"],
        }
        specs.append(prompt)
    return specs


def _picture_advanced_specs() -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    templates = [
        {
            "slug": "flight_delay",
            "title": "Flight Delay Discussion",
            "sign": "DEPARTURES",
            "setting": "waiting",
            "points": [
                "Travelers are waiting with suitcases.",
                "A staff member or information point is nearby.",
                "A clock or sign is visible in the terminal.",
                "The people appear concerned or focused.",
                "The scene suggests a travel delay or schedule issue.",
            ],
            "answer": "Several travelers are waiting with their suitcases in the terminal. A staff member or information point is nearby, and a large sign is visible above the area. The people look focused and slightly concerned. The scene suggests that there may be a delay or another travel issue.",
        },
        {
            "slug": "hotel_issue",
            "title": "Hotel Booking Problem",
            "sign": "GUEST SERVICE",
            "setting": "counter",
            "points": [
                "A guest is speaking to a hotel employee at the desk.",
                "A suitcase or travel bag is visible.",
                "A monitor or paperwork is visible behind the desk.",
                "Another traveler or helper is nearby.",
                "The interaction looks serious but professional.",
            ],
            "answer": "A guest is speaking to a hotel employee at the front desk. A suitcase is visible beside the traveler, and a monitor with paperwork can be seen behind the counter. Another person is nearby, so the lobby looks active. The interaction looks serious but professional, as if the guest needs help with a booking problem.",
        },
        {
            "slug": "deadline_review",
            "title": "Deadline Review Meeting",
            "sign": "STRATEGY ROOM",
            "setting": "meeting",
            "points": [
                "Several coworkers are discussing a project around a table.",
                "A laptop and printed documents are visible.",
                "A board, sign, or screen is visible in the room.",
                "The group appears to be reviewing an urgent task.",
                "The atmosphere looks focused and intense.",
            ],
            "answer": "Several coworkers are discussing a project around a table. A laptop and printed documents are spread out in front of them, and a board is visible in the room. The group appears to be reviewing an urgent task. The atmosphere looks focused and intense, as if a deadline is close.",
        },
        {
            "slug": "delivery_problem",
            "title": "Delivery Problem Review",
            "sign": "LOGISTICS",
            "setting": "meeting",
            "points": [
                "Boxes or packages are stacked in the room.",
                "Workers are checking a list or a laptop.",
                "Two or more people are involved in the discussion.",
                "The setting looks like a logistics or storage area.",
                "The scene suggests a problem that needs attention.",
            ],
            "answer": "Boxes are stacked in the room, and workers are checking a list on the table. Two or more people are involved in the discussion. The setting looks like a logistics area where packages are being managed. The scene suggests that there is a delivery problem that needs attention.",
        },
        {
            "slug": "event_registration",
            "title": "Event Registration Queue",
            "sign": "REGISTRATION",
            "setting": "counter",
            "points": [
                "Visitors are speaking to staff members at the desk.",
                "Printed materials or badges are visible.",
                "A line or waiting group is visible nearby.",
                "The scene looks like a formal event or conference.",
                "People appear to be checking in for the event.",
            ],
            "answer": "Visitors are speaking to staff members at a registration desk. Printed materials and badges are visible near the counter, and more people are waiting nearby. The scene looks like a formal event or conference. The people appear to be checking in before the program starts.",
        },
        {
            "slug": "restaurant_complaint",
            "title": "Restaurant Complaint",
            "sign": "SERVICE DESK",
            "setting": "counter",
            "points": [
                "A customer is explaining a problem to an employee.",
                "Food, a receipt, or a tray is visible.",
                "Another person is standing close to the counter.",
                "The scene looks like a restaurant service area.",
                "The interaction suggests a complaint or request for help.",
            ],
            "answer": "A customer is explaining a problem to an employee at a service counter. Food items or a receipt are visible near the desk, and another person is standing close by. The scene looks like a restaurant service area. The interaction suggests a complaint or a request for help.",
        },
        {
            "slug": "store_return",
            "title": "Store Return Request",
            "sign": "RETURNS",
            "setting": "counter",
            "points": [
                "A shopper is speaking to a staff member at the returns desk.",
                "A shopping bag, box, or receipt is visible.",
                "A screen or paperwork is visible behind the counter.",
                "Another customer is waiting nearby.",
                "The situation appears formal and problem-focused.",
            ],
            "answer": "A shopper is speaking to a staff member at the returns desk. A shopping bag, a box, and some paperwork are visible near the counter. Another customer is waiting nearby, so the store looks busy. The situation appears formal and problem-focused.",
        },
        {
            "slug": "travel_help",
            "title": "Travel Information Desk",
            "sign": "INFORMATION",
            "setting": "waiting",
            "points": [
                "Travelers are waiting with bags or suitcases.",
                "A help desk or information sign is visible.",
                "A clock is visible in the area.",
                "A staff member is assisting someone.",
                "The scene suggests that people need travel guidance.",
            ],
            "answer": "Travelers are waiting with bags and suitcases near an information desk. A clock and a large sign are visible in the area, and a staff member is assisting one of the travelers. The scene suggests that people need travel guidance before moving on.",
        },
        {
            "slug": "project_strategy",
            "title": "Project Strategy Session",
            "sign": "PLANNING",
            "setting": "meeting",
            "points": [
                "A team is gathered around a table for a strategy discussion.",
                "A laptop, papers, and another work item are visible.",
                "Multiple people are actively engaged.",
                "The room looks like a professional workspace.",
                "The discussion appears important and detailed.",
            ],
            "answer": "A team is gathered around a table for a strategy discussion. A laptop, papers, and other work materials are visible on the table. Multiple people are actively engaged in the conversation. The room looks like a professional workspace, and the discussion appears important and detailed.",
        },
        {
            "slug": "hospital_coordination",
            "title": "Hospital Coordination Desk",
            "sign": "CARE DESK",
            "setting": "waiting",
            "points": [
                "Visitors or patients are waiting in the seating area.",
                "A staff member is helping someone near the desk.",
                "A clock or sign is visible.",
                "Bags, papers, or personal items are visible.",
                "The atmosphere looks calm but serious.",
            ],
            "answer": "Visitors are waiting in the seating area while a staff member helps someone near the desk. A clock and a sign are visible on the wall, and personal items can be seen near the chairs. The atmosphere looks calm but serious. The scene suggests careful coordination in a hospital or clinic.",
        },
    ]
    for index in range(50):
        template = templates[index % len(templates)]
        variant = index // len(templates)
        prompt = {
            "prompt_id": f"picture_advanced_{index + 1:02d}",
            "task_type": "picture",
            "level": "advanced",
            "title": f"{template['title']} {variant + 1}",
            "instructions": "Look at the picture and write a clear description in English. Include the key people, actions, and situation shown in the scene.",
            "time_limit_sec": 720,
            "recommended_words": 140,
            "required_points": template["points"],
            "image_asset": f"assets/toeic_writing_images/advanced/scene_{index + 1:02d}.jpg",
            "source_text": None,
            "keywords": [],
            "model_answer": template["answer"],
        }
        specs.append(prompt)
    return specs


def _email_prompt(level: str, index: int) -> dict[str, Any]:
    topics = {
        "beginner": [
            ("club meeting", "English club", "attendance", "topic suggestion"),
            ("study group", "study group", "attendance", "preferred chapter"),
            ("library workshop", "library workshop", "registration", "question topic"),
            ("volunteer event", "volunteer day", "attendance", "meeting place"),
            ("team project", "team meeting", "attendance", "presentation part"),
            ("class schedule", "class review session", "attendance", "material request"),
            ("cafeteria survey", "student survey", "participation", "favorite menu"),
            ("dorm notice", "dorm meeting", "attendance", "room concern"),
            ("campus tour", "campus tour", "attendance", "start time"),
            ("part-time shift", "work schedule", "availability", "preferred shift"),
        ],
        "intermediate": [
            ("internship briefing", "internship briefing", "attendance", "document request"),
            ("training workshop", "training workshop", "attendance", "schedule question"),
            ("product demo", "product demo", "registration", "follow-up request"),
            ("seminar change", "seminar session", "attendance", "topic question"),
            ("budget meeting", "budget meeting", "attendance", "item request"),
            ("client visit", "client visit", "availability", "meeting preparation"),
            ("delivery update", "delivery review", "confirmation", "issue question"),
            ("staff orientation", "staff orientation", "attendance", "transportation question"),
            ("conference call", "conference call", "availability", "agenda request"),
            ("travel arrangement", "business trip", "confirmation", "hotel question"),
        ],
        "advanced": [
            ("vendor delay", "vendor meeting", "availability", "solution proposal"),
            ("service complaint", "service review", "attendance", "customer concern"),
            ("conference logistics", "conference planning", "attendance", "task priority"),
            ("proposal revision", "proposal review", "availability", "revision request"),
            ("policy exception", "policy meeting", "attendance", "special approval"),
            ("hotel rebooking", "travel support", "availability", "alternative request"),
            ("equipment issue", "equipment review", "attendance", "repair plan"),
            ("report deadline", "report meeting", "availability", "timeline suggestion"),
            ("client recovery", "client recovery plan", "attendance", "compensation idea"),
            ("budget revision", "budget update", "availability", "cost-saving idea"),
        ],
    }
    days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    times = ["9:00 AM", "11:00 AM", "2:00 PM", "4:00 PM", "6:00 PM"]
    sender_names = ["Mina", "Jisoo", "Daniel", "Sora", "Kevin", "Hana", "Leo", "Yuna", "Ethan", "Ari"]
    topic, meeting_name, point_b, point_c = topics[level][index % 10]
    day = days[index % len(days)]
    time = times[(index * 2) % len(times)]
    sender = sender_names[index % len(sender_names)]
    required_points = [
        f"Say whether you can attend the {meeting_name}.",
        f"Respond about {point_b}.",
        f"Include one question or suggestion about {point_c}.",
    ]
    source_text = (
        f"Hi, this is {sender}. I am writing about the {topic}. "
        f"We moved it to {day} at {time}. "
        f"Please let me know if you can come, and share your thoughts about {point_b}. "
        f"If you have any ideas about {point_c}, please include them in your reply. "
        f"Best, {sender}"
    )
    if level == "beginner":
        model_answer = (
            f"Hi {sender},\n"
            f"Thank you for the update about the {meeting_name}. "
            f"I can attend on {day} at {time}. "
            f"I am ready to talk about {point_b}. "
            f"Could you also tell me more about {point_c}? \n"
            f"Best,\nJisoo"
        )
    elif level == "intermediate":
        model_answer = (
            f"Hi {sender},\n"
            f"Thank you for your message about the {meeting_name}. "
            f"I will be able to attend on {day} at {time}. "
            f"I have reviewed my notes about {point_b}, and I can bring the related information with me. "
            f"In addition, could you let me know if there is anything specific we should prepare about {point_c}? \n"
            f"Best regards,\nJisoo"
        )
    else:
        model_answer = (
            f"Hi {sender},\n"
            f"Thank you for the detailed update regarding the {meeting_name}. "
            f"I am available to attend on {day} at {time}, and I can actively contribute to the discussion about {point_b}. "
            f"To make the meeting more productive, I would also like to suggest that we address {point_c} in advance. "
            f"Please let me know if any additional preparation is required before the meeting. \n"
            f"Sincerely,\nJisoo"
        )
    return {
        "prompt_id": f"email_{level}_{index + 1:02d}",
        "task_type": "email",
        "level": level,
        "title": f"Reply to a {meeting_name.title()} Email {index + 1}",
        "instructions": "Read the email and write a reply. Include all required points in a polite tone.",
        "time_limit_sec": 600 if level == "beginner" else 720,
        "recommended_words": 110 if level == "beginner" else 140 if level == "intermediate" else 170,
        "required_points": required_points,
        "image_asset": None,
        "source_text": source_text,
        "keywords": [],
        "model_answer": model_answer,
    }


def _opinion_prompt(level: str, index: int) -> dict[str, Any]:
    topics = {
        "beginner": [
            ("online classes", "in-person classes"),
            ("studying early", "studying late"),
            ("public transportation", "riding a bike"),
            ("working alone", "working in a team"),
            ("reading e-books", "reading paper books"),
            ("living on campus", "living at home"),
            ("watching movies at home", "watching movies in a theater"),
            ("taking notes by hand", "typing notes"),
            ("morning exercise", "evening exercise"),
            ("small classes", "large classes"),
        ],
        "intermediate": [
            ("remote work", "working in an office"),
            ("using digital textbooks", "using printed textbooks"),
            ("taking short trips", "saving money for one long trip"),
            ("learning with videos", "learning with live classes"),
            ("part-time work during the semester", "focusing only on study"),
            ("using self-service kiosks", "speaking to staff directly"),
            ("studying abroad for one semester", "taking local exchange programs"),
            ("using shared offices", "working from home"),
            ("joining many clubs", "focusing on one club"),
            ("taking intensive courses", "taking regular weekly courses"),
        ],
        "advanced": [
            ("investing in employee training", "hiring more experienced staff"),
            ("allowing hybrid work", "requiring full office attendance"),
            ("expanding public transit", "building more parking spaces"),
            ("using AI tools in education", "limiting AI use in class"),
            ("outsourcing customer support", "building an in-house support team"),
            ("holding large annual events", "running smaller events throughout the year"),
            ("using flexible deadlines", "keeping strict deadlines"),
            ("prioritizing product quality", "prioritizing low prices"),
            ("offering more remote services", "expanding in-person services"),
            ("rewarding team results", "rewarding individual results"),
        ],
    }
    first, second = topics[level][index % 10]
    question = f"Do you prefer {first} or {second}? Explain your answer."
    required_points = [
        "State your position clearly in the first part.",
        "Give at least two supporting reasons or examples.",
        "Finish with a short concluding statement.",
    ]
    if level == "beginner":
        model_answer = (
            f"I prefer {first}. First, this option is more convenient for me in my daily life. "
            f"Second, it helps me stay comfortable and focused. "
            f"For these reasons, this option is the better choice for me."
        )
    elif level == "intermediate":
        model_answer = (
            f"I prefer {first} to {second}. One reason is that it gives me more flexibility and helps me manage my schedule better. "
            f"Another reason is that it often saves time and allows me to focus on the most important tasks. "
            f"For example, I can organize my work more efficiently when I use this approach. "
            f"Overall, I believe this is the more practical option."
        )
    else:
        model_answer = (
            f"I strongly prefer {first} over {second}. My main reason is that this option creates better long-term results, even if it may require more planning at the beginning. "
            f"In addition, it often improves efficiency, communication, and overall satisfaction for the people involved. "
            f"For example, organizations that choose this approach can respond more effectively to changing needs and make more strategic decisions. "
            f"For these reasons, I believe this is the more effective and sustainable choice."
        )
    return {
        "prompt_id": f"opinion_{level}_{index + 1:02d}",
        "task_type": "opinion",
        "level": level,
        "title": f"Opinion Writing Topic {index + 1}",
        "instructions": "Write a short opinion paragraph. State your choice clearly and support it with relevant reasons.",
        "time_limit_sec": 720,
        "recommended_words": 120 if level == "beginner" else 150 if level == "intermediate" else 190,
        "required_points": required_points,
        "image_asset": None,
        "source_text": question,
        "keywords": [],
        "model_answer": model_answer,
    }


def build_prompt_bank() -> list[dict[str, Any]]:
    prompts: list[dict[str, Any]] = []

    picture_specs = (
        _picture_beginner_specs()
        + _picture_intermediate_specs()
        + _picture_advanced_specs()
    )
    for prompt in picture_specs:
        prompts.append(prompt)

    for level in ("beginner", "intermediate", "advanced"):
        for index in range(50):
            prompts.append(_email_prompt(level, index))
            prompts.append(_opinion_prompt(level, index))

    return prompts


def main() -> None:
    random.seed(SEED)
    prompt_bank = build_prompt_bank()
    PROMPT_BANK_PATH.write_text(
        json.dumps(prompt_bank, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Generated {len(prompt_bank)} prompts")


if __name__ == "__main__":
    main()
