import asyncio
import os
import unittest

from app.schemas import RoleplayGenerateRequest
from app.services.roleplay import generate, get_catalog, reset_store_for_tests


class RoleplayServiceTests(unittest.TestCase):
    def setUp(self):
        self._prev_roleplay_llm = os.environ.get("ROLEPLAY_LLM_ENABLED")
        os.environ["ROLEPLAY_LLM_ENABLED"] = "0"
        reset_store_for_tests()

    def tearDown(self):
        if self._prev_roleplay_llm is None:
            os.environ.pop("ROLEPLAY_LLM_ENABLED", None)
        else:
            os.environ["ROLEPLAY_LLM_ENABLED"] = self._prev_roleplay_llm

    def test_catalog_has_twelve_scenarios(self):
        catalog = get_catalog()
        self.assertEqual(len(catalog.items), 12)
        difficulties = {item.difficulty for item in catalog.items}
        self.assertEqual(difficulties, {"beginner", "intermediate", "advanced"})

    def test_new_session_requires_scenario_id(self):
        with self.assertRaises(Exception):
            asyncio.run(generate(RoleplayGenerateRequest()))

    def test_beginner_cafe_flow_reaches_completion(self):
        opening = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                )
            )
        )
        self.assertIn("Welcome!", opening.assistant_utterance)
        sid = opening.session_id

        turn = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="I'd like a latte, please.",
                )
            )
        )
        self.assertEqual(turn.current_stage_title, "Choose a size")

        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Medium, please.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="I'd like it iced.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Oat milk, please.",
                )
            )
        )
        final_turn = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="I'll pay by card. Thank you.",
                )
            )
        )
        self.assertTrue(final_turn.session_complete)
        self.assertEqual(final_turn.state.state, "ENDED")

    def test_cafe_extra_option_stage_accepts_skip_intent(self):
        opening = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                )
            )
        )
        sid = opening.session_id

        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="I'd like a latte, please.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Medium, please.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="I'd like it iced.",
                )
            )
        )
        skip_turn = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="No extra options, thanks.",
                )
            )
        )

        self.assertEqual(skip_turn.current_stage_title, "Respond to payment")
        self.assertIn("skip extra options", skip_turn.assistant_utterance.lower())

    def test_cafe_payment_allows_short_intent_without_forced_template(self):
        opening = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                )
            )
        )
        sid = opening.session_id

        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Latte please.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Medium.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Iced.",
                )
            )
        )
        asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="No extra options.",
                )
            )
        )
        payment = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=sid,
                    scenario_id="beginner_cafe_order",
                    difficulty="beginner",
                    user_input="Card please.",
                )
            )
        )

        self.assertTrue(payment.session_complete)
        self.assertEqual(payment.state.state, "ENDED")

    def test_off_topic_input_redirects_without_advancing(self):
        opening = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    scenario_id="beginner_ask_directions",
                    difficulty="beginner",
                )
            )
        )
        redirected = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=opening.session_id,
                    scenario_id="beginner_ask_directions",
                    difficulty="beginner",
                    user_input="I watched a great movie yesterday with my cousin.",
                )
            )
        )
        self.assertTrue(redirected.should_redirect)
        self.assertEqual(redirected.state.stage_index, 0)

    def test_hangul_input_stays_in_stage_and_scaffolds(self):
        opening = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    scenario_id="intermediate_hotel_checkin",
                    difficulty="intermediate",
                )
            )
        )
        scaffold = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    session_id=opening.session_id,
                    scenario_id="intermediate_hotel_checkin",
                    difficulty="intermediate",
                    user_input="예약했어요.",
                )
            )
        )
        self.assertFalse(scaffold.session_complete)
        self.assertEqual(scaffold.state.stage_index, 0)
        self.assertIn("Let's try that in English", scaffold.assistant_utterance)

    def test_many_turns_do_not_force_end_before_completion(self):
        opening = asyncio.run(
            generate(
                RoleplayGenerateRequest(
                    scenario_id="advanced_deadline_negotiation",
                    difficulty="advanced",
                )
            )
        )
        sid = opening.session_id
        latest = opening
        for _ in range(15):
            latest = asyncio.run(
                generate(
                    RoleplayGenerateRequest(
                        session_id=sid,
                        scenario_id="advanced_deadline_negotiation",
                        difficulty="advanced",
                        user_input="Okay.",
                    )
                )
            )
        self.assertFalse(latest.session_complete)
        self.assertNotEqual(latest.state.state, "ENDED")


if __name__ == "__main__":
    unittest.main()
