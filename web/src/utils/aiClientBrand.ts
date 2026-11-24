export interface AIClientBrand { id: string; aliases: readonly string[]; template: boolean; scale: number }

// More specific product variants precede their parent brands. This is display-only:
// a matched icon is not a verification of the OAuth client's identity.
const brands: readonly AIClientBrand[] = [
  { id: "chatgpt", aliases: ["chatgpt"], template: true, scale: 1 },
  { id: "workbuddy", aliases: ["workbuddy", "腾讯workbuddy"], template: false, scale: 1 },
  { id: "qwen", aliases: ["qwenwork", "千问办公"], template: false, scale: 1 },
  { id: "doubao", aliases: ["doubaowork", "豆包工作", "豆包办公"], template: false, scale: 1.164 },
  { id: "baidu", aliases: ["dumate", "baidudazi", "百度搭子"], template: false, scale: 1.18 },
  { id: "doubaoApp", aliases: ["doubao", "豆包"], template: false, scale: 1.243 },
  { id: "qwenApp", aliases: ["qwen", "千问", "通义千问"], template: false, scale: 1 },
  { id: "kimi", aliases: ["kimi", "月之暗面"], template: false, scale: 1 },
  { id: "deepseek", aliases: ["deepseek", "深度求索"], template: true, scale: 1 },
  { id: "zhipu", aliases: ["zhipu", "智谱", "z.ai", "zai", "glm"], template: true, scale: 1 },
  { id: "gemini", aliases: ["gemini", "双子座"], template: false, scale: 1 },
  { id: "claude", aliases: ["claude"], template: false, scale: 1 },
  { id: "cursor", aliases: ["cursor"], template: false, scale: 1 },
  { id: "windsurf", aliases: ["windsurf"], template: false, scale: 1 },
  { id: "cline", aliases: ["cline"], template: false, scale: 1 },
  { id: "cherry", aliases: ["cherrystudio", "cherry-studio"], template: false, scale: 1 },
  { id: "vscode", aliases: ["vscode", "visualstudiocode"], template: false, scale: 1 },
  { id: "codex", aliases: ["codex", "openaicodex"], template: false, scale: 1 },
];
const normalize = (name: string) => name.normalize('NFKC').toLocaleLowerCase('en-US').replace(/[\s._-]+/g, '');
export function matchAIClientBrand(name: string): AIClientBrand | undefined {
  const normalized = normalize(name);
  return brands.find(brand => brand.aliases.some(alias => normalized.includes(normalize(alias))));
}
