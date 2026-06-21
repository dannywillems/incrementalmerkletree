import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import { themes as prismThemes } from 'prism-react-renderer';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';

// The upstream repository the course is pinned against. Every source embed
// resolves against this commit so the snippets cannot drift from the prose.
const UPSTREAM = 'https://github.com/zcash/incrementalmerkletree';
const PIN = 'edf24f2b2e727776e290f292d831d4ac61c3e1bd';

// The fork that hosts the onboarding branch and the generated site.
const FORK = 'https://github.com/dannywillems/incrementalmerkletree';

const config: Config = {
  title: 'incrementalmerkletree Onboarding',
  tagline: 'A code-anchored course for the zcash/incrementalmerkletree workspace',
  favicon: 'img/favicon.svg',

  url: 'https://dannywillems.github.io',
  baseUrl: '/incrementalmerkletree/',

  organizationName: 'dannywillems',
  projectName: 'incrementalmerkletree',

  // A dead link is a real bug: the entire course points at code and specs.
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  markdown: {
    format: 'detect',
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  // Workaround for docusaurus-theme-github-codeblock@2.0.2: its
  // ReferenceCodeBlock uses a native named-capture-group regex
  // (`(?<title>...)`). Docusaurus's preset-env transforms that and, via
  // transform-runtime, injects an ESM `import` of the `wrapRegExp` helper
  // into this CJS theme module, which then fails webpack's parser. We add
  // an `enforce: 'post'` babel pass that runs AFTER that injection and
  // rewrites the injected import back to a require(). Deterministic and
  // survives a fresh npm install.
  plugins: [
    function fixGithubCodeblockEsmHelper() {
      return {
        name: 'fix-github-codeblock-esm-helper',
        configureWebpack() {
          return {
            module: {
              rules: [
                {
                  test: /docusaurus-theme-github-codeblock[\\/]cjs[\\/].*\.js$/,
                  enforce: 'post',
                  use: [
                    {
                      loader: require.resolve('babel-loader'),
                      options: {
                        babelrc: false,
                        configFile: false,
                        sourceType: 'unambiguous',
                        plugins: [
                          require.resolve(
                            '@babel/plugin-transform-modules-commonjs',
                          ),
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          };
        },
      };
    },
  ],

  themes: [
    'docusaurus-theme-github-codeblock',
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        indexBlog: false,
        indexPages: true,
        language: ['en'],
        highlightSearchTermsOnTargetPage: true,
      },
    ],
  ],

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: `${FORK}/edit/onboarding/onboarding/`,
          remarkPlugins: [remarkMath],
          rehypePlugins: [rehypeKatex],
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  // KaTeX stylesheet. The version is matched to the `katex` package that
  // `rehype-katex@7` pulls in (0.16.47); the integrity hash is computed from
  // that exact CDN file. A mismatch makes the MathML accessibility fallback
  // bleed into the visible page so formulas appear twice.
  stylesheets: [
    {
      href: 'https://cdn.jsdelivr.net/npm/katex@0.16.47/dist/katex.min.css',
      type: 'text/css',
      integrity:
        'sha384-nH0MfJ44wi1dd7w6jinlyBgljjS8EJAh2JBoRad8a3VDw2K69vfaaqm4WnR+gXtA',
      crossorigin: 'anonymous',
    },
  ],

  themeConfig: {
    announcementBar: {
      id: 'ai-generated-disclaimer',
      content:
        'This site is automatically generated using Claude Code. Errors may ' +
        'have been introduced. The code is the law, always refer to the ' +
        'source in the zcash/incrementalmerkletree workspace.',
      backgroundColor: '#fef3c7',
      textColor: '#78350f',
      isCloseable: false,
    },
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'incrementalmerkletree Onboarding',
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'courseSidebar',
          position: 'left',
          label: 'Course',
        },
        {
          href: `${FORK}/tree/onboarding`,
          label: 'Fork (onboarding)',
          position: 'right',
        },
        {
          href: UPSTREAM,
          label: 'Upstream',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Source',
          items: [
            { label: 'Fork (onboarding branch)', href: `${FORK}/tree/onboarding` },
            { label: 'Upstream zcash/incrementalmerkletree', href: UPSTREAM },
            { label: `Pinned commit ${PIN.slice(0, 10)}`, href: `${UPSTREAM}/tree/${PIN}` },
          ],
        },
        {
          title: 'References',
          items: [
            {
              label: 'incrementalmerkletree docs.rs',
              href: 'https://docs.rs/incrementalmerkletree',
            },
            { label: 'shardtree docs.rs', href: 'https://docs.rs/shardtree' },
            { label: 'bridgetree docs.rs', href: 'https://docs.rs/bridgetree' },
            {
              label: 'Zcash Protocol Specification',
              href: 'https://zips.z.cash/protocol/protocol.pdf',
            },
          ],
        },
      ],
      copyright:
        'Course content generated by Claude Code. Not authoritative. ' +
        'Code: MIT OR Apache-2.0, (c) the incrementalmerkletree authors.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['rust', 'toml', 'bash', 'json', 'yaml'],
    },
  } satisfies Preset.ThemeConfig,

  // Consumed by docusaurus-theme-github-codeblock for `reference` code blocks.
  customFields: {
    upstream: UPSTREAM,
    pin: PIN,
  },
};

export default config;
