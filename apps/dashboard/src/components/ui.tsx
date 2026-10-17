// Small building blocks in the shadcn style, styled only with design tokens.
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from 'react';

type Variant = 'primary' | 'secondary' | 'danger' | 'ghost';

const variants: Record<Variant, string> = {
  primary: 'bg-teal-500 text-on-primary hover:bg-teal-600',
  secondary: 'bg-sand-100 text-on-sand hover:bg-sand-200',
  danger: 'bg-surface text-danger border border-danger hover:bg-sand-50',
  ghost: 'bg-transparent text-ink-body hover:bg-sand-100',
};

export function Button({
  variant = 'primary',
  className = '',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return (
    <button
      className={`inline-flex min-h-[44px] items-center justify-center rounded-button px-lg text-label transition-colors duration-fast disabled:opacity-50 ${variants[variant]} ${className}`}
      {...props}
    />
  );
}

export function Input({ label, ...props }: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return (
    <label className="flex flex-col gap-xs text-label text-ink-strong">
      {label}
      <input
        className="min-h-[44px] rounded-field border border-border bg-surface px-md text-body text-ink-strong focus:border-teal-500 focus:outline-none"
        {...props}
      />
    </label>
  );
}

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-card bg-surface p-xl shadow-card ${className}`}>{children}</div>;
}

type Tone = 'neutral' | 'success' | 'warning' | 'danger' | 'info';

const tones: Record<Tone, string> = {
  neutral: 'bg-sand-100 text-ink-body',
  success: 'bg-teal-50 text-success',
  warning: 'bg-sand-100 text-warning',
  danger: 'bg-sand-50 text-danger',
  info: 'bg-teal-50 text-info',
};

export function Badge({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) {
  return <span className={`inline-flex rounded-pill px-md py-xs text-caption ${tones[tone]}`}>{children}</span>;
}

export function Notice({ children }: { children: ReactNode }) {
  return <p className="rounded-field bg-sand-100 p-md text-caption text-ink-body">{children}</p>;
}
