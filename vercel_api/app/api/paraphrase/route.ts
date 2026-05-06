import { NextRequest, NextResponse } from "next/server";
import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic();

export async function POST(req: NextRequest) {
  const { text, tone } = await req.json();

  if (!text) {
    return NextResponse.json({ error: "text is required" }, { status: 400 });
  }

  const msg = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 512,
    messages: [
      {
        role: "user",
        content: `Rewrite the following English text in a ${tone} tone.
Return ONLY valid JSON with no markdown or extra text: {"result":"...","tips":"..."}

Text: ${text}`,
      },
    ],
  });

  const raw = (msg.content[0] as { text: string }).text.trim();
  return NextResponse.json(JSON.parse(raw));
}
