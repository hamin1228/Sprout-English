import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({
    ok: true,
    message: "외부 기기 연결 성공",
    time: new Date().toISOString(),
  });
}
