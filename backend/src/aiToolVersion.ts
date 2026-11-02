import { z } from 'zod';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';

// Independent of app and protocol versions; bump only when tool definitions change.
export const MCP_TOOL_VERSION = '1';
export function versionedSchema<T extends z.ZodRawShape>(schema: z.ZodObject<T>) {
    if (Object.hasOwn(schema.shape, 'toolVersion')) throw new Error('Reserved MCP parameter: toolVersion');
    return schema.extend({ toolVersion: z.string().regex(/^[0-9]{1,9}$/)
        .describe(`Synca tool definition version: ${MCP_TOOL_VERSION}. Copy this value exactly from this definition; do not infer it from previous results.`) });
}
const isObject = (value: unknown): value is Record<string, unknown> =>
    value !== null && typeof value === 'object' && !Array.isArray(value);

// Normalize only absent fields before SDK validation. Invalid explicit values remain invalid.
export function normalizeToolVersion(body: unknown): unknown {
    return Array.isArray(body) ? body.map(normalizeCall) : normalizeCall(body);
}
function normalizeCall(body: unknown): unknown {
    if (!isObject(body) || body.method !== 'tools/call' || !isObject(body.params)) return body;
    const args = body.params.arguments;
    if (args !== undefined && !isObject(args)) return body;
    if (args && Object.hasOwn(args, 'toolVersion')) return body;
    return { ...body, params: { ...body.params, arguments: { ...args, toolVersion: '0' } } };
}
export function splitToolVersion(args: unknown) {
    const { toolVersion, ...businessArgs } = args as Record<string, unknown>;
    return { toolVersion: toolVersion as string, businessArgs };
}
export function withVersionNotice(result: CallToolResult, version: string): CallToolResult {
    if (version === MCP_TOOL_VERSION) return result;
    return { ...result, content: [...result.content, { type: 'text', text: JSON.stringify({
        type: 'tool_definition_update', reportedVersion: version === '0' ? null : version,
        currentVersion: MCP_TOOL_VERSION, refreshRecommended: true,
        message: '本次调用的工具定义版本未知或与当前版本不一致。业务结果及成功/失败状态以本次返回为准；不要重试已成功的操作。请刷新 Synca 工具列表，不能自动刷新时引导用户在当前应用中操作；不要只修改 toolVersion 来跳过提醒。刷新后按新定义发起后续调用，同一对话无需重复播报相同提醒。',
    }) }] };
}
