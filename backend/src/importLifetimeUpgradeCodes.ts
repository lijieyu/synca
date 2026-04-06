import fs from 'fs';
import path from 'path';
import { runMigrations } from './migrate.js';
import { importLifetimeUpgradeCodes } from './store.js';
import { SyncaLifetimeUpgradeOfferKind } from './types.js';

function usage(): never {
    console.error('Usage: tsx src/importLifetimeUpgradeCodes.ts --kind <monthly_to_lifetime|yearly_to_lifetime> --file <codes.csv>');
    process.exit(1);
}

function parseArgs(argv: string[]): { kind: SyncaLifetimeUpgradeOfferKind; file: string } {
    let kind: SyncaLifetimeUpgradeOfferKind | undefined;
    let file: string | undefined;

    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === '--kind') {
            const value = argv[index + 1];
            if (value === 'monthly_to_lifetime' || value === 'yearly_to_lifetime') {
                kind = value;
                index += 1;
                continue;
            }
            usage();
        }

        if (arg === '--file') {
            file = argv[index + 1];
            if (!file) usage();
            index += 1;
            continue;
        }
    }

    if (!kind || !file) usage();
    return { kind, file };
}

function parseOfferCodes(contents: string): string[] {
    const lines = contents
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0);

    if (lines.length === 0) {
        return [];
    }

    const rows = lines.map((line) => line.split(/[\t,]/).map((part) => part.trim().replace(/^"|"$/g, '')));
    const header = rows[0];
    const headerIndex = header.findIndex((column) => /offer\s*code|^code$/i.test(column));
    const startIndex = headerIndex >= 0 ? 1 : 0;
    const valueIndex = headerIndex >= 0 ? headerIndex : 0;

    return rows
        .slice(startIndex)
        .map((row) => row[valueIndex]?.trim() ?? '')
        .filter((code) => /^[A-Z0-9-]+$/i.test(code));
}

async function main() {
    const { kind, file } = parseArgs(process.argv.slice(2));
    const resolvedFile = path.resolve(process.cwd(), file);

    if (!fs.existsSync(resolvedFile)) {
        throw new Error(`file_not_found: ${resolvedFile}`);
    }

    const contents = fs.readFileSync(resolvedFile, 'utf8');
    const codes = parseOfferCodes(contents);

    if (codes.length === 0) {
        throw new Error('no_offer_codes_found');
    }

    await runMigrations();

    const now = new Date().toISOString();
    const result = await importLifetimeUpgradeCodes({
        kind,
        codes,
        now,
    });

    console.log(`[offer-codes] kind=${kind} imported=${result.inserted} existing=${result.existing} totalParsed=${codes.length}`);
}

main().then(() => process.exit(0)).catch((error) => {
    console.error('[offer-codes] import failed:', error);
    process.exit(1);
});
