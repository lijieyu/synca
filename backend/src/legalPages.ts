type Locale = 'en' | 'zh-hans';
type PageKind = 'privacy-policy' | 'terms-of-use' | 'support';

type LegalPage = {
    locale: Locale;
    kind: PageKind;
    title: string;
    description: string;
    languageLabel: string;
    alternateLanguageLabel: string;
    alternatePath: string;
    updatedAt: string;
    sections: Array<{
        heading: string;
        paragraphs: string[];
        bullets?: string[];
    }>;
};

const supportEmail = 'jieyu.li@icloud.com';

const siteMap: Record<Locale, Record<PageKind, LegalPage>> = {
    en: {
        'privacy-policy': {
            locale: 'en',
            kind: 'privacy-policy',
            title: 'Synca Privacy Policy',
            description: 'How Synca collects, uses, stores, and protects user data across iPhone and Mac.',
            languageLabel: 'English',
            alternateLanguageLabel: '简体中文',
            alternatePath: '/zh-hans/privacy-policy',
            updatedAt: 'April 4, 2026',
            sections: [
                {
                    heading: 'Overview',
                    paragraphs: [
                        'Synca is a personal cross-device capture service that helps users save text and image entries and sync them across their own devices.',
                        'This Privacy Policy explains what information we collect, how we use it, and what choices users have when using Synca.',
                    ],
                },
                {
                    heading: 'Information We Collect',
                    paragraphs: [
                        'We collect only the information reasonably necessary to provide the service.',
                    ],
                    bullets: [
                        'Account information received through Sign in with Apple, such as your Apple user identifier and, when provided by Apple, your email address.',
                        'Content you choose to create in the app, including text entries, uploaded images, and related metadata such as creation time and source device name.',
                        'Technical information required to operate the service, such as authentication tokens, device push tokens, and basic server logs.',
                    ],
                },
                {
                    heading: 'How We Use Information',
                    paragraphs: [
                        'We use collected information to authenticate users, sync content across the user’s devices, maintain badge counts, deliver background push notifications for sync, provide customer support, and improve service stability and security.',
                    ],
                },
                {
                    heading: 'How Content Is Stored',
                    paragraphs: [
                        'User account and message records are stored on Synca’s backend infrastructure. Uploaded images are stored on the server so they can be accessed by the same user on their other devices.',
                        'We do not sell personal data and we do not use user content for advertising.',
                    ],
                },
                {
                    heading: 'Sharing of Information',
                    paragraphs: [
                        'We do not share personal information with third parties except as needed to operate the service, comply with law, enforce our terms, or protect rights, safety, and security.',
                        'Examples may include Apple services for authentication and push delivery, and infrastructure providers that host the application.',
                    ],
                },
                {
                    heading: 'Data Retention',
                    paragraphs: [
                        'We retain account and content data for as long as reasonably necessary to provide the service, comply with legal obligations, resolve disputes, and enforce agreements.',
                        'If you remove content inside the app, we will attempt to remove the corresponding stored records and files from the service, subject to backup and operational constraints.',
                    ],
                },
                {
                    heading: 'Your Choices',
                    paragraphs: [
                        'You may stop using the app at any time. You can also delete content within the app and contact us if you have questions about your data.',
                    ],
                },
                {
                    heading: 'Children’s Privacy',
                    paragraphs: [
                        'Synca is not directed to children under 13, and we do not knowingly collect personal information from children under 13.',
                    ],
                },
                {
                    heading: 'Contact',
                    paragraphs: [
                        `If you have privacy questions or requests, please contact ${supportEmail}.`,
                    ],
                },
                {
                    heading: 'Changes to This Policy',
                    paragraphs: [
                        'We may update this Privacy Policy from time to time. Continued use of Synca after an updated policy becomes effective means the updated policy will apply.',
                    ],
                },
            ],
        },
        'terms-of-use': {
            locale: 'en',
            kind: 'terms-of-use',
            title: 'Synca Terms of Use',
            description: 'The rules and conditions for using Synca on iPhone and Mac.',
            languageLabel: 'English',
            alternateLanguageLabel: '简体中文',
            alternatePath: '/zh-hans/terms-of-use',
            updatedAt: 'April 4, 2026',
            sections: [
                {
                    heading: 'Acceptance of Terms',
                    paragraphs: [
                        'By accessing or using Synca, you agree to these Terms of Use. If you do not agree, please do not use the app.',
                    ],
                },
                {
                    heading: 'Service Description',
                    paragraphs: [
                        'Synca is a personal productivity tool that lets users capture text and image entries and sync them across their own devices signed in to the same account.',
                    ],
                },
                {
                    heading: 'Accounts and Access',
                    paragraphs: [
                        'Sign in with Apple is the account access method supported by Synca. You are responsible for maintaining access to your Apple account and devices.',
                    ],
                },
                {
                    heading: 'Acceptable Use',
                    paragraphs: [
                        'You agree not to misuse the service.',
                    ],
                    bullets: [
                        'Do not attempt to interfere with the normal operation, security, or availability of Synca.',
                        'Do not upload unlawful, infringing, abusive, or harmful content.',
                        'Do not attempt to gain unauthorized access to other users’ data or accounts.',
                    ],
                },
                {
                    heading: 'Access Model',
                    paragraphs: [
                        'Synca currently provides a 7-day free trial. After the trial ends, the free plan allows up to 20 new entries per day.',
                        'Synca also offers optional paid access through monthly and annual subscriptions, as well as a lifetime purchase. The pricing, billing period, renewal terms, and product details shown in the app or on the App Store at the time of purchase will control.',
                    ],
                },
                {
                    heading: 'Content and Availability',
                    paragraphs: [
                        'We may update, improve, suspend, or discontinue features at any time. We do not guarantee uninterrupted or error-free availability.',
                    ],
                },
                {
                    heading: 'Intellectual Property',
                    paragraphs: [
                        'The Synca app, branding, software, and related materials are protected by applicable intellectual property laws. You retain ownership of the content you create and upload, subject to the rights needed for us to operate the service.',
                    ],
                },
                {
                    heading: 'Disclaimer',
                    paragraphs: [
                        'Synca is provided on an “as is” and “as available” basis to the maximum extent permitted by law. We make no warranties regarding uninterrupted operation, accuracy, or fitness for a particular purpose.',
                    ],
                },
                {
                    heading: 'Limitation of Liability',
                    paragraphs: [
                        'To the maximum extent permitted by law, Synca will not be liable for indirect, incidental, special, consequential, or punitive damages, or for any loss of data, profits, or business arising from use of the service.',
                    ],
                },
                {
                    heading: 'Contact',
                    paragraphs: [
                        `For support or legal questions about these terms, contact ${supportEmail}.`,
                    ],
                },
            ],
        },
        support: {
            locale: 'en',
            kind: 'support',
            title: 'Synca Support',
            description: 'How to contact Synca support and what information to include in your request.',
            languageLabel: 'English',
            alternateLanguageLabel: '简体中文',
            alternatePath: '/zh-hans/support',
            updatedAt: 'April 4, 2026',
            sections: [
                {
                    heading: 'Contact Support',
                    paragraphs: [
                        `For product questions, account issues, bug reports, or App Review follow-up, please email ${supportEmail}.`,
                    ],
                },
                {
                    heading: 'What to Include',
                    paragraphs: [
                        'To help us resolve issues faster, please include the app platform you are using, a short description of the issue, and any relevant screenshots or reproduction steps.',
                    ],
                    bullets: [
                        'Platform: iPhone or Mac',
                        'App version, if available',
                        'A short description of the issue',
                        'Steps to reproduce the problem, if applicable',
                    ],
                },
                {
                    heading: 'Product Scope',
                    paragraphs: [
                        'Synca is designed for personal capture and cross-device sync of text and image entries using Sign in with Apple.',
                        'Synca currently provides a 7-day free trial. After the trial ends, the free plan allows up to 20 new entries per day. Users may also choose a monthly subscription, an annual subscription, or a lifetime purchase for unlimited access.',
                    ],
                },
                {
                    heading: 'Response',
                    paragraphs: [
                        'We will do our best to respond within a reasonable time based on request volume.',
                    ],
                },
            ],
        },
    },
    'zh-hans': {
        'privacy-policy': {
            locale: 'zh-hans',
            kind: 'privacy-policy',
            title: 'Synca 隐私政策',
            description: '说明 Synca 如何收集、使用、存储和保护 iPhone 与 Mac 间同步所涉及的用户数据。',
            languageLabel: '简体中文',
            alternateLanguageLabel: 'English',
            alternatePath: '/en/privacy-policy',
            updatedAt: '2026年4月4日',
            sections: [
                {
                    heading: '概述',
                    paragraphs: [
                        'Synca 是一款个人跨设备记录与同步服务，帮助用户保存文字和图片内容，并在其自己的设备之间同步。',
                        '本隐私政策说明我们会收集哪些信息、如何使用这些信息，以及用户在使用 Synca 时拥有的相关选择。',
                    ],
                },
                {
                    heading: '我们收集的信息',
                    paragraphs: [
                        '我们只收集为提供服务所合理需要的信息。',
                    ],
                    bullets: [
                        '通过 Sign in with Apple 获取的账户信息，例如 Apple 用户标识，以及在 Apple 提供的情况下包含邮箱地址。',
                        '你在应用中主动创建的内容，包括文字记录、上传图片，以及创建时间、来源设备名称等相关元数据。',
                        '为运行服务所必需的技术信息，例如登录会话令牌、设备推送令牌，以及基础服务器日志。',
                    ],
                },
                {
                    heading: '我们如何使用信息',
                    paragraphs: [
                        '我们使用这些信息来完成用户认证、在同一账户的设备间同步内容、维护角标数量、发送用于触发同步的后台推送、提供客户支持，以及改进服务的稳定性与安全性。',
                    ],
                },
                {
                    heading: '内容如何存储',
                    paragraphs: [
                        '用户账户信息和消息记录会存储在 Synca 的后端基础设施中。上传的图片会保存在服务器上，以便同一用户在其他设备上访问。',
                        '我们不会出售个人信息，也不会将用户内容用于广告用途。',
                    ],
                },
                {
                    heading: '信息共享',
                    paragraphs: [
                        '除为运行服务所必需、遵守法律义务、执行服务条款或保护权利与安全外，我们不会向第三方共享个人信息。',
                        '这可能包括用于登录与推送服务的 Apple，以及承载应用运行的基础设施服务提供商。',
                    ],
                },
                {
                    heading: '数据保留',
                    paragraphs: [
                        '我们会在为提供服务、履行法律义务、解决争议及执行协议所合理需要的期限内保留账户和内容数据。',
                        '如果你在应用内删除内容，我们会在备份和运维约束允许的前提下，尽力删除对应的存储记录与文件。',
                    ],
                },
                {
                    heading: '你的选择',
                    paragraphs: [
                        '你可以随时停止使用本应用。你也可以在应用内删除内容，并可就数据相关问题联系我们。',
                    ],
                },
                {
                    heading: '儿童隐私',
                    paragraphs: [
                        'Synca 不面向 13 岁以下儿童，我们也不会故意收集 13 岁以下儿童的个人信息。',
                    ],
                },
                {
                    heading: '联系我们',
                    paragraphs: [
                        `如有隐私相关问题或请求，请联系 ${supportEmail}。`,
                    ],
                },
                {
                    heading: '政策更新',
                    paragraphs: [
                        '我们可能会不时更新本隐私政策。更新生效后继续使用 Synca，即表示你接受更新后的政策。',
                    ],
                },
            ],
        },
        'terms-of-use': {
            locale: 'zh-hans',
            kind: 'terms-of-use',
            title: 'Synca 用户协议',
            description: '说明在 iPhone 和 Mac 上使用 Synca 时适用的规则与条件。',
            languageLabel: '简体中文',
            alternateLanguageLabel: 'English',
            alternatePath: '/en/terms-of-use',
            updatedAt: '2026年4月4日',
            sections: [
                {
                    heading: '条款接受',
                    paragraphs: [
                        '当你访问或使用 Synca 时，即表示你同意遵守本用户协议。如果你不同意，请不要使用本应用。',
                    ],
                },
                {
                    heading: '服务说明',
                    paragraphs: [
                        'Synca 是一款个人效率工具，允许用户记录文字和图片内容，并在同一账户下的个人设备之间同步。',
                    ],
                },
                {
                    heading: '账户与访问',
                    paragraphs: [
                        'Synca 当前支持通过 Sign in with Apple 登录。你需要自行维护 Apple 账户及设备的访问安全。',
                    ],
                },
                {
                    heading: '合理使用',
                    paragraphs: [
                        '你同意不会滥用本服务。',
                    ],
                    bullets: [
                        '不得干扰 Synca 的正常运行、安全性或可用性。',
                        '不得上传违法、侵权、辱骂性或有害内容。',
                        '不得尝试访问其他用户的数据或账户。',
                    ],
                },
                {
                    heading: '访问规则',
                    paragraphs: [
                        'Synca 现已提供 7 天免费试用。试用结束后，免费版用户每日最多可新增 20 条内容。',
                        'Synca 也已提供可选付费访问，包括月付订阅、年付订阅和买断版本。具体价格、计费周期、续费规则以及产品细节以应用内或 App Store 购买页面展示内容为准。',
                    ],
                },
                {
                    heading: '内容与可用性',
                    paragraphs: [
                        '我们可能随时更新、改进、暂停或停止部分功能。我们不保证服务始终连续、无错误或永不中断。',
                    ],
                },
                {
                    heading: '知识产权',
                    paragraphs: [
                        'Synca 应用、品牌、软件及相关材料受适用知识产权法律保护。你保留自己创建和上传内容的权利，但需授予我们为运行服务所必需的相关权限。',
                    ],
                },
                {
                    heading: '免责声明',
                    paragraphs: [
                        '在法律允许的最大范围内，Synca 按“现状”和“可用”基础提供。我们不对持续可用性、准确性或特定用途适用性作任何保证。',
                    ],
                },
                {
                    heading: '责任限制',
                    paragraphs: [
                        '在法律允许的最大范围内，对于因使用本服务产生的间接、附带、特殊、后果性或惩罚性损害，或任何数据、利润、业务损失，Synca 不承担责任。',
                    ],
                },
                {
                    heading: '联系我们',
                    paragraphs: [
                        `如对本协议有支持或法律相关问题，请联系 ${supportEmail}。`,
                    ],
                },
            ],
        },
        support: {
            locale: 'zh-hans',
            kind: 'support',
            title: 'Synca 支持页面',
            description: '说明如何联系 Synca 支持以及邮件中建议包含的信息。',
            languageLabel: '简体中文',
            alternateLanguageLabel: 'English',
            alternatePath: '/en/support',
            updatedAt: '2026年4月4日',
            sections: [
                {
                    heading: '联系支持',
                    paragraphs: [
                        `如有产品咨询、账户问题、Bug 反馈或 App Review 跟进事项，请发送邮件至 ${supportEmail}。`,
                    ],
                },
                {
                    heading: '建议提供的信息',
                    paragraphs: [
                        '为了更快协助你定位问题，建议在邮件中说明所使用的平台、问题描述，以及相关截图或复现步骤。',
                    ],
                    bullets: [
                        '平台：iPhone 或 Mac',
                        '应用版本号（如可提供）',
                        '问题的简要描述',
                        '如可复现，请附上复现步骤',
                    ],
                },
                {
                    heading: '产品范围',
                    paragraphs: [
                        'Synca 主要用于通过 Sign in with Apple 登录后，在个人设备之间同步文字和图片记录。',
                        'Synca 现已提供 7 天免费试用。试用结束后，免费版用户每日最多可新增 20 条内容；用户也可选择购买月付订阅、年付订阅或买断版本，以获得不限量使用权益。',
                    ],
                },
                {
                    heading: '响应说明',
                    paragraphs: [
                        '我们会根据请求量尽量在合理时间内回复。',
                    ],
                },
            ],
        },
    },
};

export function renderLegalPage(locale: Locale, kind: PageKind): string | null {
    const page = siteMap[locale]?.[kind];
    if (!page) return null;

    const sectionHtml = page.sections.map((section) => {
        const paragraphs = section.paragraphs.map((paragraph) => `<p>${paragraph}</p>`).join('');
        const bullets = section.bullets && section.bullets.length > 0
            ? `<ul>${section.bullets.map((bullet) => `<li>${bullet}</li>`).join('')}</ul>`
            : '';
        return `
            <section class="section">
                <h2>${section.heading}</h2>
                ${paragraphs}
                ${bullets}
            </section>
        `;
    }).join('');

    const navLinks = navigation(page.locale).map((item) => {
        const active = item.kind === page.kind ? 'nav-link active' : 'nav-link';
        return `<a class="${active}" href="${item.path}">${item.label}</a>`;
    }).join('');

    const labels = page.locale === 'zh-hans'
        ? {
            updated: '更新日期',
            contact: '联系邮箱',
            viewIn: '切换到',
            footer: 'Synca 支持邮箱',
        }
        : {
            updated: 'Updated',
            contact: 'Contact',
            viewIn: 'View in',
            footer: 'Synca support email',
        };

    return `<!doctype html>
<html lang="${page.locale === 'zh-hans' ? 'zh-Hans' : 'en'}">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${page.title}</title>
    <meta name="description" content="${page.description}" />
    <style>
        :root {
            color-scheme: light;
            --bg: #f5f7fb;
            --card: rgba(255, 255, 255, 0.86);
            --text: #162033;
            --muted: #58647a;
            --border: rgba(22, 32, 51, 0.1);
            --accent: #0a7a5d;
            --accent-soft: rgba(10, 122, 93, 0.1);
            --shadow: 0 20px 60px rgba(40, 60, 90, 0.12);
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            color: var(--text);
            background:
                radial-gradient(circle at top left, rgba(10, 122, 93, 0.14), transparent 32%),
                radial-gradient(circle at top right, rgba(92, 141, 255, 0.14), transparent 24%),
                linear-gradient(180deg, #f9fbff 0%, var(--bg) 100%);
            line-height: 1.65;
        }

        a { color: var(--accent); }

        .shell {
            width: min(920px, calc(100vw - 32px));
            margin: 0 auto;
            padding: 40px 0 72px;
        }

        .hero {
            padding: 28px;
            border: 1px solid var(--border);
            border-radius: 28px;
            background: var(--card);
            backdrop-filter: blur(10px);
            box-shadow: var(--shadow);
        }

        .eyebrow {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 12px;
            border-radius: 999px;
            background: var(--accent-soft);
            color: var(--accent);
            font-size: 14px;
            font-weight: 600;
        }

        h1 {
            margin: 18px 0 12px;
            font-size: clamp(32px, 5vw, 48px);
            line-height: 1.1;
            letter-spacing: -0.03em;
        }

        .hero p {
            margin: 0;
            max-width: 680px;
            color: var(--muted);
            font-size: 17px;
        }

        .meta {
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            margin-top: 22px;
            color: var(--muted);
            font-size: 14px;
        }

        .switcher {
            display: inline-flex;
            gap: 10px;
            margin-top: 18px;
            flex-wrap: wrap;
        }

        .switcher a,
        .support-chip {
            display: inline-flex;
            align-items: center;
            min-height: 40px;
            padding: 0 14px;
            border: 1px solid var(--border);
            border-radius: 999px;
            background: #fff;
            text-decoration: none;
            color: var(--text);
            font-weight: 600;
        }

        .content {
            margin-top: 22px;
            padding: 12px;
            border-radius: 28px;
            background: rgba(255, 255, 255, 0.55);
            border: 1px solid rgba(255, 255, 255, 0.65);
            box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.8);
        }

        .nav {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
            padding: 10px;
        }

        .nav-link {
            display: inline-flex;
            align-items: center;
            min-height: 40px;
            padding: 0 14px;
            border-radius: 999px;
            text-decoration: none;
            color: var(--muted);
            background: transparent;
        }

        .nav-link.active {
            background: #fff;
            color: var(--text);
            border: 1px solid var(--border);
            box-shadow: 0 8px 24px rgba(19, 36, 66, 0.08);
        }

        .panel {
            padding: 10px;
        }

        .section {
            padding: 22px 18px;
            background: rgba(255, 255, 255, 0.82);
            border: 1px solid var(--border);
            border-radius: 22px;
        }

        .section + .section {
            margin-top: 14px;
        }

        h2 {
            margin: 0 0 10px;
            font-size: 21px;
            line-height: 1.2;
        }

        p, li {
            color: var(--muted);
            font-size: 16px;
        }

        p {
            margin: 0 0 10px;
        }

        ul {
            margin: 12px 0 0 20px;
            padding: 0;
        }

        footer {
            margin-top: 18px;
            padding: 0 10px;
            color: var(--muted);
            font-size: 13px;
        }

        @media (max-width: 640px) {
            .shell { width: min(100vw - 20px, 920px); padding-top: 20px; padding-bottom: 40px; }
            .hero { padding: 22px; border-radius: 24px; }
            .content { border-radius: 24px; }
            .section { padding: 18px 16px; border-radius: 18px; }
        }
    </style>
</head>
<body>
    <main class="shell">
        <section class="hero">
            <div class="eyebrow">Synca · ${page.languageLabel}</div>
            <h1>${page.title}</h1>
            <p>${page.description}</p>
            <div class="meta">
                <span>${labels.updated}: ${page.updatedAt}</span>
                <span class="support-chip">${labels.contact}: <a href="mailto:${supportEmail}">${supportEmail}</a></span>
            </div>
            <div class="switcher">
                <a href="${page.alternatePath}">${labels.viewIn} ${page.alternateLanguageLabel}</a>
            </div>
        </section>
        <section class="content">
            <nav class="nav" aria-label="Page navigation">
                ${navLinks}
            </nav>
            <div class="panel">
                ${sectionHtml}
            </div>
        </section>
        <footer>
            ${labels.footer}: <a href="mailto:${supportEmail}">${supportEmail}</a>
        </footer>
    </main>
</body>
</html>`;
}

function navigation(locale: Locale): Array<{ kind: PageKind; label: string; path: string }> {
    if (locale === 'zh-hans') {
        return [
            { kind: 'privacy-policy', label: '隐私政策', path: '/zh-hans/privacy-policy' },
            { kind: 'terms-of-use', label: '用户协议', path: '/zh-hans/terms-of-use' },
            { kind: 'support', label: '支持页面', path: '/zh-hans/support' },
        ];
    }

    return [
        { kind: 'privacy-policy', label: 'Privacy Policy', path: '/en/privacy-policy' },
        { kind: 'terms-of-use', label: 'Terms of Use', path: '/en/terms-of-use' },
        { kind: 'support', label: 'Support', path: '/en/support' },
    ];
}
