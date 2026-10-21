import React, { forwardRef } from 'react';

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  error?: boolean;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { className = '', error = false, disabled = false, type = 'text', ...props },
  ref
) {
  return (
    <input
      ref={ref}
      type={type}
      disabled={disabled}
      className={`h-8 w-full rounded-md border bg-white dark:bg-stone-900 px-2.5 py-1 text-xs text-stone-900 dark:text-stone-100 placeholder:text-stone-400 dark:placeholder:text-stone-500 transition-colors disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)] ${
        error
          ? 'border-rose-400 dark:border-rose-700 focus-visible:ring-rose-500'
          : 'border-stone-200 dark:border-stone-800'
      } ${className}`}
      {...props}
    />
  );
});
