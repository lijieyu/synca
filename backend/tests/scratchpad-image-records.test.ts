import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {afterEach, beforeAll, beforeEach, expect, it} from 'vitest';
import {db} from '../src/db.js';
import {runMigrations} from '../src/migrate.js';
import {createMessage, resetDb, updateMessageText} from '../src/store.js';
import {deleteScratchpadImage, writeScratchpad} from '../src/scratchpad.js';

let account: string, asset: string, directory: string;
const now = () => new Date().toISOString();
const reference = () => `![picture](synca-image:${asset})`;
const remove = () => deleteScratchpadImage(account, asset, directory, directory);
async function user() {
    const id = randomUUID();
    await db.insertInto('users').values({id, apple_user_id: randomUUID(), nickname: 'Image reference fixture', created_at: now(), updated_at: now()}).execute();
    return id;
}
async function record(content = reference(), owner = account, collected = false) {
    const id = randomUUID();
    await createMessage({id, userId: owner, type: 'text', textContent: content, now: now(), isCollected: collected});
    return id;
}
async function expectProtected() {
    expect(await remove()).toBe(409);
    expect(await fs.readFile(path.join(directory, 'fixture.png'), 'utf8')).toBe('isolated fixture');
    expect(await db.selectFrom('messages').select(['is_deleted', 'attachment_purged']).where('id', '=', asset).executeTakeFirstOrThrow())
        .toEqual({is_deleted: 0, attachment_purged: 0});
}
beforeAll(runMigrations);
beforeEach(async () => {
    await resetDb();
    account = await user(); asset = randomUUID();
    directory = await fs.mkdtemp(path.join(os.tmpdir(), 'synca-image-records-'));
    await fs.writeFile(path.join(directory, 'fixture.png'), 'isolated fixture');
    await createMessage({id: asset, userId: account, type: 'image', imagePath: 'fixture.png', scratchpadAsset: true, isCollected: true, now: now()});
});
afterEach(async () => { await fs.rm(directory, {recursive: true, force: true}); });

it('preserves bytes referenced only by a saved text record, then permits deletion after editing away the reference', async () => {
    const id = await record();
    await expectProtected();
    const current = await db.selectFrom('messages').select('updated_at').where('id', '=', id).executeTakeFirstOrThrow();
    expect(await updateMessageText({id, userId: account, textContent: 'reference removed', expectedUpdatedAt: current.updated_at})).toHaveProperty('message');
    expect(await remove()).toBe(200);
    await expect(fs.stat(path.join(directory, 'fixture.png'))).rejects.toMatchObject({code: 'ENOENT'});
});
it('protects collected records and case variants of image references', async () => {
    await record(`![picture](SYNCA-IMAGE:${asset.toUpperCase()})`, account, true);
    await expectProtected();
});
it('conservatively preserves references inside code so later editing cannot lose the original image', async () => {
    await record('```\n' + reference() + '\n```');
    await expectProtected();
});
const encodedReferences = [
    ['decimal colon', (id: string) => `synca-image&#58;${id}`],
    ['named colon', (id: string) => `synca-image&colon;${id}`],
    ['escaped colon', (id: string) => `synca-image\\:${id}`],
    ['encoded UUID character', (id: string) => `synca-image:&#${id.charCodeAt(0)};${id.slice(1)}`],
    ['fully numeric destination', (id: string) => [...`synca-image:${id}`].map(c => `&#x${c.charCodeAt(0).toString(16)};`).join('')],
    ['escaped UUID hyphens', (id: string) => `synca-image:${id.replaceAll('-', '\\-')}`],
] as const;
for (const [name, encode] of encodedReferences) {
    it(`protects a record reference with ${name}`, async () => {
        await record(`![picture](${encode(asset)})`);
        await expectProtected();
    });
    it(`validates and protects a scratchpad reference with ${name}`, async () => {
        const content = `![picture](${encode(asset)})`;
        expect((await writeScratchpad(account, {content, expectedRevision: 0, mutationId: randomUUID()})).status).toBe(200);
        await expectProtected();
        const foreign = `![picture](${encode(randomUUID())})`;
        expect((await writeScratchpad(account, {content: foreign, expectedRevision: 1, mutationId: randomUUID()})).status).toBe(422);
    });
}
it('does not let a foreign account block deletion or delete the owner asset', async () => {
    const other = await user();
    await record(reference(), other);
    expect(await deleteScratchpadImage(other, asset, directory, directory)).toBe(404);
    expect(await fs.readFile(path.join(directory, 'fixture.png'), 'utf8')).toBe('isolated fixture');
    expect(await remove()).toBe(200);
});
it('ignores soft-deleted text records', async () => {
    const id = await record();
    await db.updateTable('messages').set({is_deleted: 1}).where('id', '=', id).execute();
    expect(await remove()).toBe(200);
});
it('sees a record creation that commits while image deletion is queued', async () => {
    let entered!: () => void, release!: () => void;
    const enteredPromise = new Promise<void>(resolve => { entered = resolve; });
    const releasePromise = new Promise<void>(resolve => { release = resolve; });
    const writing = createMessage({id: randomUUID(), userId: account, type: 'text', textContent: reference(), now: now(),
        beforeCommit: async () => { entered(); await releasePromise; }});
    await enteredPromise;
    const deleting = remove();
    release();
    await writing;
    expect(await deleting).toBe(409);
    await expectProtected();
});
it('sees a record update that commits while image deletion is queued', async () => {
    const id = await record('no picture yet');
    let entered!: () => void, release!: () => void;
    const enteredPromise = new Promise<void>(resolve => { entered = resolve; });
    const releasePromise = new Promise<void>(resolve => { release = resolve; });
    const writing = db.transaction().execute(async trx => {
        await trx.updateTable('messages').set({text_content: reference()}).where('id', '=', id).execute();
        entered(); await releasePromise;
    });
    await enteredPromise;
    const deleting = remove();
    release(); await writing;
    expect(await deleting).toBe(409);
    await expectProtected();
});
