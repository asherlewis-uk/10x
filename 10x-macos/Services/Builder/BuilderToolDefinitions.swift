import Foundation

/// Tool definitions sent to Claude via the proxy endpoint.
/// These match the Anthropic tool_use JSON schema format.
struct BuilderIntegrationToolAvailability: Sendable {
    var hasSupabaseAccess: Bool = false
    // Superwall removed in 11x local cockpit — always false

    static let none = BuilderIntegrationToolAvailability()
}

enum BuilderToolDefinitions {
    typealias ToolDefinition = [String: Any]
    typealias ToolSchema = [String: Any]

    // MARK: - Mode Tool Sets

    static let planTools: [ToolDefinition] = flatten(toolGroups: planToolGroups)
    static let buildTools: [ToolDefinition] = flatten(toolGroups: buildToolGroups)

    static func tools(
        for mode: ProjectMode,
        integrationAvailability: BuilderIntegrationToolAvailability = .none
    ) -> [ToolDefinition] {
        let toolGroups: [[ToolDefinition]]
        switch mode {
        case .plan:
            toolGroups = planToolGroups
        case .build:
            toolGroups = buildToolGroups
        }

        return flatten(toolGroups: toolGroups + integrationToolGroups(for: integrationAvailability))
    }

    private static let planToolGroups: [[ToolDefinition]] = [
        sharedTools,
        projectStatusTools,
        modeTools,
        skillTools,
    ]

    private static let buildToolGroups: [[ToolDefinition]] = [
        fileTools,
        reviewTools,
        sharedTools,
        projectStatusTools,
        modeTools,
        skillTools,
    ]

    private static func flatten(toolGroups: [[ToolDefinition]]) -> [ToolDefinition] {
        toolGroups.flatMap { $0 }
    }

    // MARK: - File Tools

    static let fileTools: [ToolDefinition] = [
        tool(
            name: "write_file",
            description: """
                Write a file to the project. Creates the file if it doesn't exist, \
                overwrites it if it does. The path should follow project conventions: \
                App.swift for entry point, ContentView.swift for root view, \
                Views/Name.swift for views, Components/Name.swift for reusable components, \
                Models/Name.swift for models and view models. \
                For small, targeted changes to existing files, prefer edit_file instead. \
                When creating multiple files in one pass, send at most 3 related write_file calls \
                together in the same response rather than spreading them across separate turns. \
                Only batch files that belong to the same small task or code area.
                """,
            schema: objectSchema(
                properties: [
                    "path": stringProperty("File path relative to project root (e.g., 'ContentView.swift', 'Views/HomeView.swift')"),
                    "content": stringProperty("Complete file content. Must be valid Swift code."),
                ],
                required: ["path", "content"]
            )
        ),
        tool(
            name: "edit_file",
            description: """
                Make a surgical edit to an existing file by replacing a specific string. \
                Much more efficient than write_file — only sends the changed portion instead \
                of rewriting the entire file. The old_string must match EXACTLY (including \
                whitespace and indentation). Use this for small, targeted changes. \
                For large rewrites or new files, use write_file instead. \
                When you already know several related edits are needed, send at most 3 related \
                edit_file calls together in the same response. Only batch edits that belong to \
                the same small task or code area.
                """,
            schema: objectSchema(
                properties: [
                    "path": stringProperty("Path of the existing file to edit"),
                    "old_string": stringProperty("The exact string to find and replace. Must match the file content exactly, including indentation."),
                    "new_string": stringProperty("The replacement string. Must be different from old_string."),
                ],
                required: ["path", "old_string", "new_string"]
            )
        ),
        tool(
            name: "read_files",
            description: """
                Read one or more files from the project. Returns the content of each file. \
                Use this to examine files before modifying them. Batch all files you need \
                into a single call instead of reading one at a time across multiple turns.
                """,
            schema: objectSchema(
                properties: [
                    "paths": arrayProperty(
                        items: ["type": "string"],
                        description: "Array of file paths to read (e.g., ['ContentView.swift', 'Models/Recipe.swift'])",
                        minItems: 1
                    ),
                ],
                required: ["paths"]
            )
        ),
        tool(
            name: "delete_file",
            description: "Delete a file from the project.",
            schema: objectSchema(
                properties: [
                    "path": stringProperty("Path of the file to delete"),
                ],
                required: ["path"]
            )
        ),
        tool(
            name: "list_files",
            description: """
                List files in the project. Returns all files if no pattern is given. \
                If a glob pattern is provided, returns only matching files. \
                Use this to understand project structure or discover files by name/extension.
                """,
            schema: objectSchema(
                properties: [
                    "pattern": stringProperty("Optional glob pattern to filter files (e.g., '*.swift', 'Views/**/*.swift', '*Model*'). Omit to list all files."),
                ]
            )
        ),
        tool(
            name: "search_files",
            description: """
                Search across all PROJECT files for a text pattern (like grep). \
                Returns matching lines with file paths and line numbers. \
                THIS is the tool to use when looking for code in the project — NOT web_search. \
                Use this to find where a symbol, string, or pattern is used across the codebase. \
                Supports regular expressions. Essential before making changes that affect multiple files.
                """,
            schema: objectSchema(
                properties: [
                    "pattern": stringProperty("Text or regex pattern to search for (e.g., 'NavigationStack', 'func fetch.*async', '@State.*count')"),
                    "file_pattern": stringProperty("Optional glob pattern to filter files (e.g., '*.swift', 'Views/*.swift'). Searches all files if omitted."),
                    "case_sensitive": booleanProperty("Whether the search is case-sensitive. Default true."),
                ],
                required: ["pattern"]
            )
        ),
        tool(
            name: "run_command",
            description: """
                Run a shell command on the user's macOS device in the project directory. \
                Use this for build checks (swiftc, swift build), verifying code compiles, \
                checking for syntax errors, or inspecting the local filesystem. \
                The command executes locally on the user's Mac. \
                Prefer file tools for reading/writing project files. Timeout: 30 seconds.
                """,
            schema: objectSchema(
                properties: [
                    "command": stringProperty("The shell command to execute (e.g., 'swiftc -typecheck ContentView.swift', 'ls -la')"),
                ],
                required: ["command"]
            )
        ),
    ]

    // MARK: - Shared Tools

    static let sharedTools: [ToolDefinition] = [
        tool(
            name: "web_search",
            description: """
                Search the INTERNET for external research only. Use this for official docs, SDK \
                docs, UI patterns, competitor apps, and other non-project sources. If the request \
                already matches a skill in prompt context, load that skill first. If a specific \
                page matters, follow with `scrape_url`. For time-sensitive queries, use the \
                current date/year from prompt context instead of guessing a stale year. NEVER use \
                this for project code.
                """,
            schema: objectSchema(
                properties: [
                    "query": stringProperty("The search query"),
                ],
                required: ["query"]
            )
        ),
        tool(
            name: "scrape_url",
            description: """
                Fetch and read a specific external web page from a URL. Use this when the user \
                provides a URL directly, or when `web_search` surfaces a page you need to inspect \
                in detail. Retrieves the page, extracts readable content, and converts it into \
                markdown/text for grounded follow-up reasoning. Use ONLY for external pages and \
                reference material — NEVER for project files or local code.
                """,
            schema: objectSchema(
                properties: [
                    "url": stringProperty("The full http(s) URL to read"),
                ],
                required: ["url"]
            )
        ),
        tool(
            name: "ask_user",
            description: """
                Ask the user 1-4 clarifying questions. Use this when you need more information \
                to proceed effectively — e.g., design preferences, feature priorities, \
                target audience, or choices between alternatives. You can batch related questions \
                into a single call to save time, or ask one at a time for deeper exploration. \
                Prefer multiple-choice questions with concrete options, and do not ask fully open-ended questions. \
                The user's responses will be returned as the tool result.
                """,
            schema: objectSchema(
                properties: [
                    "questions": arrayProperty(
                        items: objectSchema(
                            properties: [
                                "question": stringProperty("The question to ask. Be specific."),
                                "options": arrayProperty(
                                    items: ["type": "string"],
                                    description: "Optional list of choices for the user."
                                ),
                                "multi_select": booleanProperty("If true, user can select multiple options. Default false."),
                            ],
                            required: ["question"]
                        ),
                        description: "Array of 1-4 questions to ask the user.",
                        minItems: 1,
                        maxItems: 4
                    ),
                ],
                required: ["questions"]
            )
        ),
        tool(
            name: "set_project_identity",
            description: """
                Set the project name and optionally use a user-uploaded image as the app icon. \
                Reference the uploaded image by its filename exactly when one is available. \
                Use this as soon as the user confirms the app name. The name can always be changed later. \
                Do not call this again if the project already has that exact name unless you are also applying \
                a newly uploaded icon.
                """,
            schema: objectSchema(
                properties: [
                    "name": stringProperty("A short, polished app name. Ask the user first if the name is not already confirmed."),
                    "image_filename": stringProperty("Optional. The exact filename of a user-uploaded image attachment to use as the app icon."),
                ],
                required: ["name"]
            )
        ),
    ]

    // MARK: - Review Tools

    static let reviewTools: [ToolDefinition] = [
        tool(
            name: "update_app_store_assets",
            description: """
                Generate or refresh App Store assets for the current app. \
                This creates the icon, markdown description, and App Store screenshots from real \
                captured screens in Development. Use `assets` when refreshing only one asset. \
                For simple screenshot list edits, use `screenshot_action` with 1-based positions to \
                remove or move an existing screenshot locally without regenerating the whole set. \
                App Store screenshots need at least 3 distinct captured screens; otherwise tell the \
                user more captures are needed.
                """,
            schema: objectSchema(
                properties: [
                    "assets": arrayProperty(
                        items: stringProperty(
                            "Asset kind to refresh.",
                            enumValues: ["icon", "description", "screenshots"]
                        ),
                        description: "Which assets to update. Omit only for a full refresh."
                    ),
                    "brief": stringProperty("Optional creative direction or constraints to apply while generating the assets."),
                    "source_view_names": arrayProperty(
                        items: ["type": "string"],
                        description: "Optional captured view names to prioritize for App Store screenshots."
                    ),
                    "apply_icon_to_project": booleanProperty("Whether the generated icon should also become the current project app icon. Default true."),
                    "screenshot_action": stringProperty(
                        "Optional fast local screenshot list change. Use this only for deterministic remove or move requests.",
                        enumValues: ["remove", "move"]
                    ),
                    "screenshot_position": [
                        "type": "integer",
                        "description": "Optional 1-based screenshot position to remove or move. Required when screenshot_action is set.",
                        "minimum": 1,
                    ],
                    "move_to_position": [
                        "type": "integer",
                        "description": "Optional 1-based destination position when screenshot_action is `move`.",
                        "minimum": 1,
                    ],
                ]
            )
        )
    ]

    static let listScreensTool = tool(
        name: "list_screens",
        description: """
            List the real captured app screens currently available for App Store work. \
            Use this to get the exact sourceCaptureID values and names for the attached \
            images before replacing App Store screenshots.
            """,
        schema: objectSchema(properties: [:])
    )

    static let updateAppStoreDetailsTool = tool(
        name: "update_app_store_details",
        description: """
            Update the App Store details in one call. Provide a replacement description, \
            a replacement screenshot set, or both together. Use `list_screens` first when \
            you need exact sourceCaptureID values for screenshot pairing.
            """,
        schema: objectSchema(
            properties: [
                "description": objectSchema(
                    properties: [
                        "headline": stringProperty("Primary App Store headline."),
                        "subtitle": stringProperty("Short supporting subtitle."),
                        "shortBlurb": stringProperty("Compact marketing blurb."),
                        "fullDescription": stringProperty("Full App Store description in markdown. No headings."),
                        "featureBullets": arrayProperty(
                            items: ["type": "string"],
                            description: "Short plain-text feature bullets shown in the review export overview."
                        ),
                    ],
                    required: ["headline", "subtitle", "shortBlurb", "fullDescription", "featureBullets"]
                ),
                "screenshots": arrayProperty(
                    items: reviewScreenshotDraftSchema,
                    description: "Optional full replacement screenshot set in display order.",
                    minItems: 1,
                    maxItems: 5
                ),
            ]
        )
    )

    // MARK: - Project Status Tools

    static let projectStatusTools: [ToolDefinition] = [
        tool(
            name: "update_project_status",
            description: """
                Update the project plan, milestone checklist, roadmap warnings, or any combination \
                of those in a single call. Provide at least one field. \
                The plan is a structured markdown document guiding the building phase — include \
                app concept, target audience, key features, screen list, design system choices, \
                and note whether v1 should stay mock/local-first or wire a real integration now. \
                Only include external integrations and production environment variables when the \
                user explicitly wants live setup in this phase. \
                Tasks are high-level milestones (6-10 max) using checkboxes (- [ ] / - [x]) \
                to track progress. Update and check off milestones as work progresses. \
                Warnings are concise roadmap caveats for requests that are out of scope or only \
                partially supportable right now. Warnings should reflect the explicit Delivery \
                Scope Contract in the system prompt, not guessed product heuristics.
                """,
            schema: objectSchema(
                properties: [
                    "plan": stringProperty("The full project plan in markdown format."),
                    "tasks": stringProperty("The full milestone checklist as markdown. Use - [ ] for pending and - [x] for completed. Keep items high-level and tangible."),
                    "warnings": arrayProperty(
                        items: objectSchema(
                            properties: [
                                "severity": stringProperty("Optional warning severity.", enumValues: ["warning"]),
                                "title": stringProperty("Short warning title shown in the roadmap."),
                                "requested_capability": stringProperty("Optional. The capability the user asked for."),
                                "message": stringProperty("A precise explanation of the limitation."),
                                "fallback": stringProperty("Optional. The best next step or supported fallback."),
                            ],
                            required: ["title", "message"]
                        ),
                        description: "Optional roadmap warnings. Send the full active list each time, or an empty array to clear warnings."
                    ),
                ]
            )
        ),
        tool(
            name: "update_project_dependencies",
            description: """
                Replace the project's required dependency manifest in one call. Use this right after \
                the first real plan is written in plan mode, and update it only when requirements \
                materially change. For mock-first MVPs, send an empty `dependencies` array. Only \
                include integrations, client-safe runtime values, backend-only secrets that should \
                stay off-device, and temporary development dependencies that must be removed before \
                shipping when the user explicitly wants live setup in this phase.
                """,
            schema: objectSchema(
                properties: [
                    "dependencies": arrayProperty(
                        items: objectSchema(
                            properties: [
                                "id": stringProperty("Stable machine-readable dependency ID."),
                                "title": stringProperty("Short user-facing dependency title."),
                                "summary": stringProperty("What this dependency is for and what the user should do."),
                                "setup_surface": stringProperty(
                                    "Where the user should configure this dependency.",
                                    enumValues: ProjectSetupSurface.allCases.map(\.rawValue)
                                ),
                                "integration_id": stringProperty(
                                    "Optional built-in integration ID when this maps to Integrations.",
                                    enumValues: ProjectIntegrationID.allCases.map(\.rawValue)
                                ),
                                "backend_provider_id": stringProperty(
                                    "Optional managed backend provider ID when this maps to Backend.",
                                    enumValues: ProjectBackendProviderID.allCases.map(\.rawValue)
                                ),
                                "backend_capability_ids": arrayProperty(
                                    items: ["type": "string"],
                                    description: "Optional managed backend capabilities required for this dependency."
                                ),
                                "env_keys": arrayProperty(
                                    items: ["type": "string"],
                                    description: "Environment variable keys tied to this dependency."
                                ),
                                "safety": stringProperty(
                                    "Where this dependency belongs.",
                                    enumValues: ProjectDependencySafety.allCases.map(\.rawValue)
                                ),
                                "allows_mock_data_until_configured": booleanProperty(
                                    "Whether the app should continue with dummy/mock data until setup is complete."
                                ),
                            ],
                            required: ["id", "title", "summary", "safety", "allows_mock_data_until_configured"]
                        ),
                        description: "Full replacement dependency manifest. Send the entire active list every time."
                    ),
                ],
                required: ["dependencies"]
            )
        ),
    ]

    // MARK: - Mode Tools

    static let modeTools: [ToolDefinition] = [
        tool(
            name: "change_mode",
            description: """
                Switch the project mode. Use this when the conversation naturally shifts focus:
                - Switch to 'plan' when the user wants to research, brainstorm, or rethink the concept
                - Switch to 'build' only after the user explicitly approved the plan or clearly asked to start building
                The mode change updates the UI and will affect your system prompt in the next message.
                """,
            schema: objectSchema(
                properties: [
                    "mode": stringProperty("The mode to switch to.", enumValues: ["plan", "build"]),
                    "reason": stringProperty("Brief explanation of why you're switching modes."),
                ],
                required: ["mode"]
            )
        ),
    ]

    // MARK: - Skill Tools

    static let skillTools: [ToolDefinition] = [
        tool(
            name: "list_skills",
            description: """
                List all available skills with their names, descriptions, and \
                common trigger phrases. Use this early when the request enters a \
                specialized domain and you need to identify which skills should \
                be loaded before planning or implementation.
                """,
            schema: objectSchema(properties: [:])
        ),
        tool(
            name: "use_skill",
            description: """
                Load a specific skill by name. Use this immediately for user-required skills, \
                or whenever the request clearly matches the skills catalog. If the match is \
                already obvious from prompt context, call this directly instead of going to \
                `web_search` first.
                """,
            schema: objectSchema(
                properties: [
                    "name": stringProperty("The exact skill name from the required skills context or the full skills catalog returned by list_skills."),
                ],
                required: ["name"]
            )
        ),
    ]

    // MARK: - Integration Tools

    private static func integrationToolGroups(
        for availability: BuilderIntegrationToolAvailability
    ) -> [[ToolDefinition]] {
        var groups: [[ToolDefinition]] = []
        if availability.hasSupabaseAccess {
            groups.append(supabaseTools)
        }
        // Superwall tools removed in 11x local cockpit
        return groups
    }

    private static let supabaseReadProperties: ToolSchema = [
        "schema": stringProperty("Optional schema name. Defaults to `public`."),
        "table": stringProperty("Optional table name. Omit to list user-created tables."),
        "columns": arrayProperty(
            items: ["type": "string"],
            description: "Optional column names to select. Defaults to all columns."
        ),
        "filters": objectProperty("Optional equality filters keyed by column name."),
        "limit": integerProperty(
            "Optional maximum row count. Defaults to 25, max 200.",
            minimum: 1,
            maximum: 200
        ),
    ]

    private static let supabaseWriteProperties: ToolSchema = [
        "schema": stringProperty("Optional schema name. Defaults to `public`."),
        "table": stringProperty("Table name."),
        "operation": stringProperty("Write operation.", enumValues: ["insert", "update", "delete"]),
        "values": objectProperty("Column/value object for a single insert row or an update payload."),
        "rows": arrayProperty(
            items: ["type": "object"],
            description: "Optional array of row objects for multi-row inserts.",
            minItems: 1
        ),
        "filters": objectProperty("Equality filters keyed by column name. Required for update and delete."),
    ]

    private static let supabaseManageSettingsProperties: ToolSchema = [
        "action": stringProperty("Settings action.", enumValues: ["describe_auth", "update_auth"]),
        "signups_enabled": booleanProperty("Optional global sign-up enabled flag."),
        "email_enabled": booleanProperty("Optional email auth enabled flag."),
        "email_confirmations_enabled": booleanProperty("Optional email confirmation requirement. Set false to auto-confirm email signups."),
        "secure_email_change_enabled": booleanProperty("Optional email change confirmation requirement."),
        "allow_unverified_email_sign_ins": booleanProperty("Optional allow-unverified-email sign-in flag."),
        "phone_enabled": booleanProperty("Optional phone auth enabled flag."),
        "phone_confirmations_enabled": booleanProperty("Optional phone confirmation requirement."),
        "anonymous_users_enabled": booleanProperty("Optional anonymous sign-in enabled flag."),
        "password_min_length": integerProperty("Optional minimum password length.", minimum: 6),
        "leaked_password_protection_enabled": booleanProperty("Optional breached-password protection flag."),
        "refresh_token_rotation_enabled": booleanProperty("Optional refresh token rotation flag."),
        "single_session_per_user": booleanProperty("Optional single active session per user flag."),
        "require_reauthentication_for_password_changes": booleanProperty("Optional require-reauthentication flag for password changes."),
        "rate_limit_email_sent": integerProperty("Optional email sends per hour limit.", minimum: 1),
        "rate_limit_sms_sent": integerProperty("Optional SMS sends per hour limit.", minimum: 1),
        "apple_enabled": booleanProperty("Optional Apple auth enabled flag."),
        "google_enabled": booleanProperty("Optional Google auth enabled flag."),
    ]

    private static let backendManageProperties: ToolSchema = [
        "action": stringProperty(
            "Backend action.",
            enumValues: ["status", "link_provider", "upsert_function", "deploy", "invoke", "set_secret", "list_logs"]
        ),
        "provider_id": stringProperty(
            "Optional backend provider identifier. Defaults to `supabase`.",
            enumValues: ProjectBackendProviderID.allCases.map(\.rawValue)
        ),
        "function_name": stringProperty("Optional function name for function actions."),
        "summary": stringProperty("Optional short function summary used in Backend."),
        "verify_jwt": booleanProperty("Optional Supabase verify-jwt flag for the function. Defaults to true."),
        "source_code": stringProperty("Optional complete TypeScript source for `supabase/functions/<name>/index.ts`. Required for `upsert_function`."),
        "request_json": objectProperty("Optional JSON request body for invoke actions."),
        "auth_mode": stringProperty(
            "Optional invoke auth mode. Use `user_jwt` to test a protected function as the current signed-in user, `anon` to use the publishable key bearer token, or `none` to omit the bearer token.",
            enumValues: ["user_jwt", "anon", "none"]
        ),
        "secret_name": stringProperty("Optional backend secret name for `set_secret`."),
        "secret_value": stringProperty("Optional backend secret value for `set_secret`."),
        "tail": integerProperty("Optional max log entries to return. Defaults to 10.", minimum: 1, maximum: 50),
    ]

    private static let superwallManageProperties: ToolSchema = [
        "action": stringProperty(
            "Superwall action.",
            enumValues: [
                "status",
                "bootstrap_project",
                "bootstrap_starter_monetization",
                "sync_preview_test_user",
                "list_paywalls",
                "list_templates",
                "open_dashboard",
                "open_paywalls",
                "open_templates",
            ]
        ),
        "organization_id": stringProperty("Optional Superwall organization ID for `bootstrap_project`."),
        "project_id": stringProperty("Optional Superwall project ID to link instead of creating a new one."),
        "application_id": stringProperty("Optional Superwall application ID to link instead of creating a new one."),
        "paywall_id": stringProperty("Optional existing Superwall paywall ID to use for starter bootstrap."),
        "preview_app_user_id": stringProperty("Optional preview/test app user ID. Defaults to `tenx-preview-<projectId>`."),
        "placements": arrayProperty(
            items: ["type": "string"],
            description: "Optional explicit placement names for the starter campaign.",
            minItems: 1
        ),
    ]

    static let supabaseTools: [ToolDefinition] = [
        tool(
            name: "backend_manage",
            description: """
                Manage the connected Supabase backend for the current project through one compact tool. \
                Use this for Backend workspace actions such as linking the connected Supabase project, \
                scaffolding named Edge Functions, deploying a function, invoking a function, setting \
                backend secrets, or reviewing recent backend logs. Do not use this to build an open HTTP proxy.
                """,
            schema: objectSchema(
                properties: backendManageProperties,
                required: ["action"]
            )
        ),
        tool(
            name: "supabase_read_tables",
            description: """
                Read data from the connected Supabase project or list its user-created tables. \
                These tools are only present when Supabase is connected in Integrations for the \
                current project. If `table` is omitted, this returns the current user-created table \
                list instead of row data. When `schema` and `table` are provided, this can also inspect \
                non-public tables such as `storage.buckets`.
                """,
            schema: objectSchema(properties: supabaseReadProperties)
        ),
        tool(
            name: "supabase_write_tables",
            description: """
                Insert, update, or delete rows in the connected Supabase project, including scoped \
                writes to non-public tables such as `storage.buckets` when `schema` and `table` are \
                provided. The runtime will automatically ask the user for approval before the first \
                write in a session. Use `rows` or `values` for inserts, `values` plus `filters` for \
                updates, and `filters` for deletes.
                """,
            schema: objectSchema(
                properties: supabaseWriteProperties,
                required: ["table", "operation"]
            )
        ),
        tool(
            name: "supabase_execute_sql",
            description: """
                Execute SQL against the connected Supabase project, including schema changes, RLS policies, \
                indexes, migrations, storage bucket setup, storage policies, or multi-statement SQL. Use \
                `supabase_write_tables` for scoped row-level bucket metadata edits and this tool for broader \
                bucket or policy setup. The runtime will automatically ask the user for approval before the \
                first execution in a session.
                """,
            schema: objectSchema(
                properties: [
                    "sql": stringProperty("The SQL to execute in the connected Supabase project."),
                ],
                required: ["sql"]
            )
        ),
        tool(
            name: "supabase_manage_settings",
            description: """
                Read or update the connected Supabase project's auth settings. The runtime \
                will automatically ask the user for approval before changing settings. Use \
                `describe_auth` to inspect auth settings or `update_auth` to manage signups, \
                email/phone auth, confirmation requirements, password and session policy, \
                auth rate limits, Apple auth, or Google auth.
                """,
            schema: objectSchema(properties: supabaseManageSettingsProperties)
        ),
    ]

    static let superwallTools: [ToolDefinition] = [
        tool(
            name: "superwall_manage",
            description: """
                Manage the connected Superwall account for the current project. Use this to inspect \
                link status, bootstrap or link the Superwall project and iOS application, attach the \
                starter entitlement/products/preview-campaign setup to an existing paywall, sync the \
                preview test user, list paywalls or templates, or open the Superwall dashboard pages. \
                Create, duplicate, or import the paywall in Superwall first; the runtime will automatically ask \
                the user for approval before mutating connected Superwall resources.
                """,
            schema: objectSchema(
                properties: superwallManageProperties,
                required: ["action"]
            )
        ),
    ]

    // MARK: - Schema Helpers

    private static func tool(name: String, description: String, schema: ToolSchema) -> ToolDefinition {
        [
            "name": name,
            "description": description,
            "input_schema": schema,
        ]
    }

    private static func objectSchema(properties: ToolSchema, required: [String] = []) -> ToolSchema {
        var schema: ToolSchema = [
            "type": "object",
            "properties": properties,
        ]

        if !required.isEmpty {
            schema["required"] = required
        }

        return schema
    }

    private static func stringProperty(_ description: String, enumValues: [String]? = nil) -> ToolSchema {
        var schema: ToolSchema = [
            "type": "string",
            "description": description,
        ]

        if let enumValues {
            schema["enum"] = enumValues
        }

        return schema
    }

    private static func booleanProperty(_ description: String) -> ToolSchema {
        [
            "type": "boolean",
            "description": description,
        ]
    }

    private static func objectProperty(_ description: String) -> ToolSchema {
        [
            "type": "object",
            "description": description,
        ]
    }

    private static func integerProperty(
        _ description: String,
        minimum: Int? = nil,
        maximum: Int? = nil
    ) -> ToolSchema {
        var schema: ToolSchema = [
            "type": "integer",
            "description": description,
        ]

        if let minimum {
            schema["minimum"] = minimum
        }

        if let maximum {
            schema["maximum"] = maximum
        }

        return schema
    }

    private static func arrayProperty(
        items: ToolSchema,
        description: String,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) -> ToolSchema {
        var schema: ToolSchema = [
            "type": "array",
            "items": items,
            "description": description,
        ]

        if let minItems {
            schema["minItems"] = minItems
        }

        if let maxItems {
            schema["maxItems"] = maxItems
        }

        return schema
    }

    private static let reviewScreenshotDraftSchema: ToolSchema = objectSchema(
        properties: [
            "id": stringProperty("Optional stable screenshot ID. Omit to create a new one."),
            "sourceCaptureID": stringProperty("Exact source capture ID for the attached app screen."),
            "sourceViewName": stringProperty("Optional source view name. Omit when sourceCaptureID is enough."),
            "headline": stringProperty("Primary screenshot headline."),
            "subheadline": stringProperty("Optional supporting screenshot subheadline."),
            "backgroundColors": arrayProperty(
                items: ["type": "string"],
                description: "One or more hex colors for the screenshot background gradient.",
                minItems: 1
            ),
            "accentColor": stringProperty("Optional hex accent color."),
            "deviceScale": ["type": "number", "description": "Optional device size multiplier. Default 1.0."],
            "rotationDegrees": ["type": "number", "description": "Optional device rotation in degrees. Default 0."],
            "textPlacement": stringProperty("Optional text placement.", enumValues: ["top", "bottom"]),
            "textAlignment": stringProperty("Optional text alignment.", enumValues: ["leading", "center", "trailing"]),
            "headlineFontFamily": stringProperty("Optional headline font family.", enumValues: ["system", "rounded", "serif", "condensed", "monospaced"]),
            "headlineWeight": stringProperty("Optional headline font weight.", enumValues: ["regular", "medium", "semibold", "bold", "black"]),
            "headlineItalic": booleanProperty("Optional. Italicize the headline."),
            "headlineAllCaps": booleanProperty("Optional. Uppercase the headline."),
            "headlineScale": ["type": "number", "description": "Optional headline scale. Default 1.0."],
            "headlineTracking": ["type": "number", "description": "Optional headline letter spacing. Default -1.0."],
            "headlineWidthRatio": ["type": "number", "description": "Optional headline width ratio. Default 0.92."],
            "subheadlineFontFamily": stringProperty("Optional subheadline font family.", enumValues: ["system", "rounded", "serif", "condensed", "monospaced"]),
            "subheadlineWeight": stringProperty("Optional subheadline weight.", enumValues: ["regular", "medium", "semibold", "bold", "black"]),
            "subheadlineItalic": booleanProperty("Optional. Italicize the subheadline."),
            "subheadlineScale": ["type": "number", "description": "Optional subheadline scale. Default 1.0."],
            "textToDeviceSpacing": ["type": "number", "description": "Optional spacing between copy and device. Default 40."],
            "screenZoom": ["type": "number", "description": "Optional crop zoom for the source screen. Default 1.0."],
            "screenFocusX": ["type": "number", "description": "Optional horizontal crop focus from 0 to 1. Default 0.5."],
            "screenFocusY": ["type": "number", "description": "Optional vertical crop focus from 0 to 1. Default 0.5."],
        ],
        required: ["sourceCaptureID", "headline", "backgroundColors"]
    )
}
