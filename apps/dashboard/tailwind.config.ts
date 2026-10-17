import type { Config } from 'tailwindcss';
import { tokens } from './tailwind.tokens';

// Only design tokens (docs/DESIGN.md): no raw colors or sizes in components.
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: tokens as unknown as Config['theme'],
  },
} satisfies Config;
