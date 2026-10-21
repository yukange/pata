import React, { forwardRef } from 'react';
import { Loader2 } from 'lucide-react';

export type ButtonVariant = 'default' | 'secondary' | 'outline' | 'ghost' | 'destructive' | 'warning' | 'brand';
export type ButtonSize = 'sm' | 'default' | 'lg' | 'icon';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
}

const variantStyles: Record<ButtonVariant, string> = {
  // default: Follows macOS system accent
  default:
    'bg-[var(--pata-accent)] text-white hover:opacity-90 shadow-2xs active:opacity-95',
  secondary:
    'bg-stone-200/70 dark:bg-stone-800 text-stone-800 dark:text-stone-200 hover:bg-stone-300/80 dark:hover:bg-stone-700 active:bg-stone-300 dark:active:bg-stone-700/90 shadow-2xs',
  outline:
    'border border-stone-200 dark:border-stone-800 bg-transparent text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 active:bg-stone-200/50 dark:active:bg-stone-700/50',
  ghost:
    'bg-transparent text-stone-600 dark:text-stone-400 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 hover:text-stone-900 dark:hover:text-stone-100 active:bg-stone-200 dark:active:bg-stone-800',
  destructive:
    'bg-rose-600 dark:bg-rose-600 text-white hover:bg-rose-700 dark:hover:bg-rose-700 shadow-2xs active:bg-rose-800',
  warning:
    'bg-amber-600 dark:bg-amber-600 text-white hover:bg-amber-700 dark:hover:bg-amber-700 shadow-2xs active:bg-amber-800',
  brand:
    'bg-emerald-700 dark:bg-emerald-600 text-white hover:bg-emerald-800 dark:hover:bg-emerald-700 shadow-2xs active:bg-emerald-900',
};

const sizeStyles: Record<ButtonSize, string> = {
  sm: 'h-7 px-2.5 text-xs rounded-md gap-1.5',
  default: 'h-8 px-3 text-xs rounded-md gap-2',
  lg: 'h-9 px-4 text-sm rounded-lg gap-2',
  icon: 'h-7 w-7 p-0 flex items-center justify-center rounded-md shrink-0',
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'default',
    size = 'default',
    loading = false,
    disabled = false,
    className = '',
    children,
    type = 'button',
    ...props
  },
  ref
) {
  const isDisabled = disabled || loading;

  return (
    <button
      ref={ref}
      type={type}
      disabled={isDisabled}
      className={`inline-flex items-center justify-center font-medium transition-all select-none cursor-pointer disabled:opacity-50 disabled:pointer-events-none disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)] focus-visible:ring-offset-1 ${variantStyles[variant]} ${sizeStyles[size]} ${className}`}
      {...props}
    >
      {loading ? (
        <>
          <Loader2 className="w-3.5 h-3.5 animate-spin shrink-0" />
          {size !== 'icon' && children}
        </>
      ) : (
        children
      )}
    </button>
  );
});
