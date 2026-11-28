export default {
  test: {
    globals: true,
    include: ['tests/**/*.test.ts'],
    // These use Node's test runner and are run separately by test:node.
    exclude: ['tests/markdown-parser.test.ts', 'tests/scratchpad.test.ts', 'tests/collections.test.ts', 'tests/change-notifications.test.ts'],
    fileParallelism: false,
  },
};
