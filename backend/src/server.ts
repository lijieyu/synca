import 'dotenv/config';
import app from './app.js';
import { runMigrations } from './migrate.js';

const port = Number(process.env.PORT ?? 3000);

// Run migrations on startup
await runMigrations();

const server = app.listen(port, '0.0.0.0', () => {
    console.log(`synca-backend listening on 0.0.0.0:${port}`);
});

process.on('SIGINT', () => {
    server.close(() => process.exit(0));
});

process.on('SIGTERM', () => {
    server.close(() => process.exit(0));
});
