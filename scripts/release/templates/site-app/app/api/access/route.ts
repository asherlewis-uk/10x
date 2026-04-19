import { NextRequest, NextResponse } from "next/server";

const ACCESS_COOKIE = "downloads_access";
const ACCESS_CODE = process.env.DOWNLOADS_ACCESS_CODE ?? "1MILLIONMRR";

function normalizeNextPath(raw: FormDataEntryValue | null) {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!value.startsWith("/") || value.startsWith("//")) {
    return "/stable";
  }
  if (value.startsWith("/access") || value.startsWith("/api/access")) {
    return "/stable";
  }
  return value;
}

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const accessCode = typeof formData.get("accessCode") === "string"
    ? String(formData.get("accessCode")).trim()
    : "";
  const nextPath = normalizeNextPath(formData.get("next"));

  if (accessCode !== ACCESS_CODE) {
    const redirectUrl = new URL("/access", request.url);
    redirectUrl.searchParams.set("error", "1");
    if (nextPath && nextPath !== "/stable") {
      redirectUrl.searchParams.set("next", nextPath);
    }
    return NextResponse.redirect(redirectUrl, { status: 303 });
  }

  const response = NextResponse.redirect(new URL(nextPath, request.url), { status: 303 });
  response.cookies.set({
    name: ACCESS_COOKIE,
    value: "granted",
    httpOnly: true,
    sameSite: "lax",
    secure: request.nextUrl.protocol === "https:",
    path: "/",
    maxAge: 60 * 60 * 24 * 30,
  });
  return response;
}
