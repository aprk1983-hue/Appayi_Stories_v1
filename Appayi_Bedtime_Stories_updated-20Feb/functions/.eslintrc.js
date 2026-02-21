module.exports = {
  root: true,
  env: { node: true, es2020: true },
  parser: "@typescript-eslint/parser",
  parserOptions: { ecmaVersion: 2020, sourceType: "module" },
  plugins: ["@typescript-eslint"],
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
  ],
  ignorePatterns: ["lib/**", "node_modules/**"],
  rules: {
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
    "max-len": "off",
    "object-curly-spacing": "off",
    "block-spacing": "off",
    "brace-style": "off",
    "comma-spacing": "off",
    "space-before-blocks": "off",
    "key-spacing": "off",
    "arrow-parens": "off",
    "@typescript-eslint/no-explicit-any": "off"
  }
};
