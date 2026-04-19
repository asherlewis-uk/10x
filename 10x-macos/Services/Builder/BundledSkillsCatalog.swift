import Foundation

enum BundledSkillsCatalog {
    nonisolated static var registry: [SkillRegistryEntry] {
        allSkills.map { skill in
            SkillRegistryEntry(
                name: skill.name,
                description: skill.description,
                tags: skill.tags
            )
        }
    }

    nonisolated static func skill(named rawName: String) -> SkillContentResponse? {
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let skill = allSkills.first(where: { $0.name == normalizedName }) else {
            return nil
        }

        return SkillContentResponse(
            name: skill.name,
            description: skill.description,
            tags: skill.tags,
            content: skill.content
        )
    }

    private nonisolated static let allSkills: [BundledSkill] = [
        BundledSkill(
            name: "ai-models",
            description: "Load before writing code that calls OpenAI. Covers current request shape, environment variables, and iOS-safe integration guidance.",
            tags: ["ai", "openai", "models", "chat", "vision"],
            content: """
            # OpenAI Integration Skill

            Use this before writing any production OpenAI integration code.

            ## Recommended iOS Approach

            - In TenX projects, the managed OpenAI integration collects `OPENAI_API_KEY`.
            - Treat `OPENAI_API_KEY` as a Hosted Key.
            - Save it in Integrations under Hosted Keys. 10x syncs it to Supabase secrets instead of writing it into project files or generated source.
            - Do not read `OPENAI_API_KEY` from app code. Route OpenAI calls through Backend or another server-side path.
            - Never ask the user to paste `OPENAI_API_KEY` into chat. Builder chat messages are persisted with the project conversation, so direct them to Integrations instead.

            ## Current Defaults

            - Preferred flagship model: `gpt-5.4`
            - Preferred balanced model: `gpt-5.4-mini`

            ## Request Format

            Use the Chat Completions endpoint with `max_completion_tokens`, not `max_tokens`, when targeting GPT-5 family models.

            ```json
            {
              "model": "gpt-5.4-mini",
              "max_completion_tokens": 1024,
              "messages": [
                {"role": "developer", "content": "You are a helpful assistant."},
                {"role": "user", "content": "Hello!"}
              ]
            }
            ```

            ## Swift Pattern

            ```swift
            import Foundation

            struct AIProxyService {
              let baseURL: URL

              func chat(messages: [[String: String]]) async throws -> String {
                var request = URLRequest(url: baseURL.appendingPathComponent("chat"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                  "model": "gpt-5.4-mini",
                  "max_completion_tokens": 1024,
                  "messages": messages,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, _) = try await URLSession.shared.data(for: request)
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let choices = payload?["choices"] as? [[String: Any]]
                let message = choices?.first?["message"] as? [String: Any]
                return message?["content"] as? String ?? ""
              }
            }
            ```

            ## TenX Integrations

            - `OPENAI_API_KEY`: Hosted Key synced to Supabase secrets

            Tell the user to add this in the Integrations tab, not the old Environment tab or the chat.
            """
        ),
        BundledSkill(
            name: "supabase",
            description: "Load before building Supabase auth, database, or migration-aware tooling. Covers native Apple/Google sign-in, email-only flows, and client-vs-admin credentials.",
            tags: ["supabase", "auth", "database", "postgres", "apple", "google", "rls"],
            content: supabaseSkillContent
        ),
        BundledSkill(
            name: "superwall",
            description: "Load before building Superwall SDK integrations, dashboard bootstrapping, placements, campaigns, or subscription-state handling.",
            tags: ["superwall", "paywall", "subscription", "placements", "campaigns"],
            content: superwallSkillContent
        ),
        BundledSkill(
            name: "backend",
            description: "Load before building managed Supabase backend work. Covers Backend workspace rules, named Edge Functions, backend secrets, deploy approvals, and no-proxy constraints.",
            tags: ["backend", "supabase", "functions", "serverless", "secrets"],
            content: backendSkillContent
        ),
    ]

    private nonisolated static let supabaseSkillContent = """
    # Supabase Integration Skill

    Use this before building Supabase auth, database access, or schema tooling.

    ## Client-safe Inputs

    The managed client-facing Supabase setup should start by enabling or connecting the built-in Supabase integration.

    Do not ask the user to manually paste `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY`.

    Once connected, the app imports the client runtime it needs automatically.

    Never ship `service_role`, `sb_secret_...`, database passwords, or other admin credentials in an iOS app.

    ## Delivery Rules

    - Do not claim Supabase is fully wired until the app compiles and at least one real auth path plus one real data read/write path are verified.
    - Do not silently fall back to `SampleData`, fake profile rows, hardcoded PR lists, or placeholder dates/settings once the user asked for a real Supabase integration. Use explicit loading, empty, and error states instead.
    - Keep one source of truth for remote state. Views should read from a shared store/service instead of mixing live data with local mocks.
    - Do not promise offline cache, sync, or SwiftData unless you actually implement it.
    - For real Supabase auth setups, disable Confirm Email by default so email signups can complete immediately. Only keep or turn it back on when the user explicitly asks for verified-email onboarding.
    - When the user asks why Apple, Google, or email confirmation is not working, do not only say "configure Supabase." Tell them the exact dashboard page, the fields they must fill in, the callback or redirect URLs involved, and whether the fix lives in app code or in Supabase.
    - In user-facing summaries, do not center the response on imported client runtime key names. Point the user to Integrations > Client Keys / Backend Keys unless they explicitly ask which keys were saved.

    ## What Lives Where

    - App code scope: native Apple/Google button flow, `redirectTo` or deep-link handling, and exchanging the returned credential into a real Supabase session.
    - Supabase scope: provider enable toggles, provider Client IDs and Client Secrets, Confirm Email behavior, Site URL, Redirect URLs, Email Templates, and SMTP delivery.
    - Point the user to the exact dashboard pages: Auth > Providers, Auth > URL Configuration, and Auth > Email Templates.

    ## Client Implementation Rules

    - Prefer the official Supabase Swift SDK for auth, session refresh, and database access when you can add the package cleanly.
    - If you use the SDK path, add or link it deliberately in the Xcode project first. Do not assume it is already installed.
    - If the SDK is not already linked and you intentionally use REST instead, say so and implement secure session persistence, refresh, sign-out cleanup, and typed error handling. Do not ship a throwaway in-memory auth client just to avoid dependency setup.

    ## Recommended iOS Auth Choice

    - Fastest MVP: email-only
    - Best native social sign-in on iOS: Sign in with Apple
    - Add Google after Apple when your audience expects it
    - Before wiring auth, ask which auth type to start with first: email + password, magic link, Apple, Google, or a mixed setup.
    - Ask whether the user wants a temporary dev bypass for now during local iteration. Keep that bypass clearly development-only and easy to remove later.

    ## Email-only

    Start here when speed matters:

    - Email + password is the simplest native iOS path.
    - Email OTP / magic link removes passwords but needs redirect URL setup.

    ```swift
    let session = try await supabase.auth.signIn(
      email: email,
      password: password
    )
    ```

    ```swift
    try await supabase.auth.signInWithOTP(
      email: email,
      redirectTo: URL(string: "your-app-scheme://auth/callback")!
    )
    ```

    ## Email Confirmation

    - Email confirmation is managed in Supabase, not in the iOS client.
    - Default to Confirm Email off in Auth > Providers > Email unless the user explicitly wants verified-email onboarding.
    - Use Auth > URL Configuration to set Site URL and the Redirect URLs used by confirmation, magic-link, and reset-password flows.
    - Use Auth > Email Templates to edit the confirm-signup, magic-link, and reset-password templates or redirect behavior.
    - If confirmation emails need to reach real users outside your team before launch, set up production SMTP as part of the Supabase auth handoff.

    ## Sign in with Apple

    For iOS and macOS, prefer native `AuthenticationServices`.

    ```swift
    import AuthenticationServices
    import Supabase

    let idToken = String(data: credential.identityToken!, encoding: .utf8)!

    _ = try await supabase.auth.signInWithIdToken(
      credentials: .init(
        provider: .apple,
        idToken: idToken
      )
    )
    ```

    Rules:

    - Request `.fullName` and `.email` scopes.
    - Apple only returns the user's full name on the first authorization. If `credential.fullName` is present, persist it immediately with `supabase.auth.update(user: UserAttributes(...))`.
    - Prefer native Apple auth on iOS/macOS. Avoid Apple's web OAuth flow for native apps unless you explicitly need it.
    - Apple's web OAuth configuration requires rotating the signing secret every 6 months.
    - Supabase setup: create an App ID, Services ID, and Sign in with Apple key in Apple Developer, then add the generated secret in Supabase Auth > Sign In / Providers > Apple. Register all Apple client IDs you actually use under Client IDs: the Services ID for web OAuth plus native bundle IDs for native Apple sign-in.
    - Use `https://<project-ref>.supabase.co/auth/v1/callback` as the callback URL when configuring the Apple provider.
    - Do not render `SignInWithAppleButton` unless the handler completes the real credential exchange into a real session.

    ## Sign in with Google

    Use the native Google Sign-In SDK, or a real `ASWebAuthenticationSession` OAuth callback flow, then pass the returned credential into Supabase.

    ```swift
    import GoogleSignIn
    import Supabase

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootController)
    let idToken = result.user.idToken!.tokenString

    try await supabase.auth.signInWithIdToken(
      credentials: .init(
        provider: .google,
        idToken: idToken
      )
    )
    ```

    Provider setup rules:

    - Configure the Google provider in Supabase with a web OAuth client ID and secret.
    - Create the OAuth client in Google Cloud and add the exact Supabase callback URI as an authorized redirect URI. For most projects that is `https://<project-ref>.supabase.co/auth/v1/callback`, but custom auth domains use their own host instead, for example `https://auth.example.invalid/auth/v1/callback`.
    - If you use multiple client IDs across web + iOS, keep the web client ID first in the comma-separated list.
    - Prefer native Google sign-in when the SDK is already linked. A browser callback flow is also acceptable if it completes a real session.

    ## Provider Authenticity Rules

    - Do not use Apple or Google branding for a fake local sign-in path.
    - If the UI says Apple or Google, the handler must complete the real provider flow and exchange the returned credential or callback into a real session.
    - If provider configuration is not ready yet, add a separate `Demo Sign In`, `Preview Account`, or similar development-only path instead of a fake provider button.
    - Demo auth must be clearly labeled as demo or development-only, easy to remove, and close enough to the real signed-in state to let the user test onboarding, gated screens, and profile flows.
    - Do not leave `TODO: replace with real Apple/Google auth` behind a real-looking provider button.

    ## Database Rules

    - Put user-facing data access behind RLS.
    - Treat client runtime credentials and management/admin credentials as different trust levels.
    - Do not let generic builder shell commands read admin Supabase secrets directly.
    - In 10x, when Supabase is connected for the current project, use the built-in Supabase tools instead of asking the user to open the SQL editor manually.
    - Use `supabase_read_tables` to inspect schema or rows, including storage metadata like `storage.buckets` when you pass `schema` and `table`.
    - Use `supabase_write_tables` for scoped row changes, including bucket rows in `storage.buckets`, `supabase_execute_sql` for DDL/migrations/RLS/indexes/storage buckets/storage policies, and `supabase_manage_settings` for auth settings.
    - `supabase_manage_settings` can describe or update signups, email and phone auth, confirmation requirements, anonymous users, password policy, session policy, auth rate limits, Apple auth, and Google auth for the connected project.
    - If the user asks to create or alter tables, buckets, policies, indexes, or functions, use `supabase_execute_sql` and let the runtime request approval automatically.
    - Storage bucket creation and policy changes are in scope through the built-in Supabase tools. Do not promise object uploads unless you already have the file or bytes to upload.

    ## Exact Migration-aware Schema Simulation

    The correct client-side path is local, not `10x-api`:

    1. Start from remote schema and migration history.
    2. Rebuild a local shadow database.
    3. Apply migrations in order.
    4. Apply generated SQL.
    5. Show the resulting schema diff.

    This exact path needs separate local tooling and separate admin/database credentials outside the minimal client-facing integration page.
    """

    private nonisolated static let superwallSkillContent = """
    # Superwall Integration Skill

    Use this before building Superwall SDK code, paywall placements, dashboard automation, or subscription-aware gating.

    ## Account Connection Rules

    - Prefer the built-in Connect Superwall flow in Integrations.
    - The org-scoped Superwall management API key belongs in local Keychain only.
    - Do not ask the user to paste the org API key into chat, project files, or normal environment variables.
    - `SUPERWALL_PUBLIC_API_KEY` is the only Superwall key that should enter the app runtime.
    - When Superwall is connected and `superwall_manage` is available, use it instead of telling the user to create dashboard resources manually.
    - When the user asks how to edit a paywall, include the linked Superwall dashboard or paywalls page when project context provides one.
    - In user-facing summaries, do not center the response on the imported public runtime key name. Point the user to Integrations > Client Keys unless they explicitly ask which key was saved.

    ## What Lives Where

    - App code / 10x scope: `SUPERWALL_PUBLIC_API_KEY`, SDK configuration, placement names, preview test user wiring, and starter bootstrap resources.
    - Superwall dashboard scope: paywall design, copy, template choice, assets, product attachments, campaign targeting, and experiments.
    - Tell the user explicitly that visual paywall editing happens in Superwall, not in the iOS codebase.

    ## Builder Workflow

    - First bootstrap or link the Superwall project and iOS application.
    - Then have the user create, duplicate, or import the paywall in Superwall.
    - After that, seed starter monetization by attaching an entitlement, products, and a preview-only campaign to the selected existing paywall.
    - Keep the initial setup preview-safe. Default to test-mode and preview-only targeting until production handoff is explicit.
    - Reuse saved placement names, products, and linked dashboard resources from project context instead of creating duplicates.

    ## Runtime Rules

    - Use a dedicated Superwall wrapper/service. Do not scatter raw `Superwall.shared` calls throughout views.
    - The wrapper should own:
      - configure
      - placement registration
      - subscription-status observation
      - identify/reset around auth changes
      - user attributes
      - deep-link handling when used
    - In `DEBUG`, prefer the deterministic preview user (`tenx-preview-<projectId>`) and set a preview attribute such as `tenx_preview = true` when no real identity exists.
    - In `DEBUG`, use `.whenEnabledForUser` when the preview user has been synced for test mode; otherwise fall back to `.always`.
    - In `Release`, use `.automatic` and remove synthetic preview identity/attributes.
    - Read `SUPERWALL_PUBLIC_API_KEY` from `ProcessInfo.processInfo.environment` first, then from a shipping-safe fallback such as Info.plist or XCConfig.

    ## Placement Rules

    - Do not collapse the app into one generic `showPaywall` placement.
    - Use one placement per monetization moment.
    - Always include `upgrade_prompt`.
    - Include `onboarding_complete` when onboarding exists.
    - For premium features, use names like `premium_<feature_slug>`.

    ## SDK And Dashboard Rules

    - Prefer the official Superwall iOS SDK.
    - Add the `Superwall-iOS` package only when generated code actually imports `SuperwallKit`.
    - If RevenueCat is already present, acknowledge the branch and avoid inventing a new first-class purchase-controller path unless the user explicitly wants that.
    - Treat "configured" as preview/test ready, not launch ready.
    - Before launch, replace preview-only campaign targeting, confirm App Store Connect products, verify TestFlight purchases, and move the public API key into real release configuration.
    """

    private nonisolated static let backendSkillContent = """
    # Managed Backend Skill

    Use this before planning or implementing managed backend work.

    ## Workspace Rules

    - Managed Supabase backend work belongs in the `Backend` workspace, not `Integrations`.
    - Keep the base client-facing Supabase integration limited to `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
    - When the plan or prompt context includes a backend dependency, treat that as already-requested setup and continue from the Backend path.

    ## Backend Design Rules

    - Build named JSON endpoints such as `create_checkout_session`, `sync_calendar`, or `receive_webhook`.
    - Do not build a generic open proxy that forwards arbitrary URLs, headers, or methods.
    - Default new functions to authenticated endpoints unless the use case is clearly public or webhook-style.
    - Keep request/response payloads explicit and stable.

    ## Secrets

    - Backend-only secrets belong in Backend, not in client runtime variables or generated Swift source.
    - Use `backend_manage` with `set_secret` for backend secrets.
    - Never ask the user to paste backend secrets into the Integrations UI when the managed backend path is in scope.

    ## Execution Rules

    - Use `backend_manage` for `status`, `link_provider`, `upsert_function`, `deploy`, `invoke`, `set_secret`, and `list_logs`.
    - `upsert_function` should keep the local `supabase/functions/<name>/index.ts` scaffold as the source of truth.
    - Ask for approval before deploys and before creating or rotating secrets. The runtime will pause automatically when needed.
    - After backend code changes, prefer `invoke` smoke checks against the named function when the endpoint is testable.

    ## Supabase Notes

    - This managed backend path is Supabase-only in v1.
    - Use Supabase Edge Functions for backend API logic and secret-backed integrations.
    - Do not claim that Supabase Edge Functions are universally Pro-only. If a deploy is blocked by the linked project's plan, describe it as a project plan or capability restriction and point the user to the Backend or Supabase integration note.
    - Keep auth, database, and schema-specific client guidance in the separate `supabase` skill.
    """
}

private struct BundledSkill {
    let name: String
    let description: String
    let tags: [String]
    let content: String
}
