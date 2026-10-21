import React from 'react';
import { Menu as BaseMenu } from '@base-ui/react/menu';

export const DropdownMenu = BaseMenu.Root;
export const DropdownMenuTrigger = BaseMenu.Trigger;

export interface DropdownMenuContentProps extends React.HTMLAttributes<HTMLDivElement> {
  side?: 'top' | 'bottom' | 'left' | 'right';
  align?: 'start' | 'center' | 'end';
  sideOffset?: number;
}

export const DropdownMenuContent = React.forwardRef<HTMLDivElement, DropdownMenuContentProps>(
  function DropdownMenuContent({ children, className = '', side = 'bottom', align = 'end', sideOffset = 4, ...props }, ref) {
    return (
      <BaseMenu.Portal>
        <BaseMenu.Positioner side={side} align={align} sideOffset={sideOffset} className="z-50">
          <BaseMenu.Popup
            ref={ref}
            className={`min-w-[140px] rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-1 shadow-lg pata-pop focus:outline-none ${className}`}
            {...props}
          >
            {children}
          </BaseMenu.Popup>
        </BaseMenu.Positioner>
      </BaseMenu.Portal>
    );
  }
);

export interface DropdownMenuItemProps extends React.ButtonHTMLAttributes<HTMLDivElement> {
  destructive?: boolean;
  disabled?: boolean;
  closeOnClick?: boolean;
}

export const DropdownMenuItem = React.forwardRef<HTMLDivElement, DropdownMenuItemProps>(
  function DropdownMenuItem({ children, className = '', destructive = false, disabled = false, ...props }, ref) {
    return (
      <BaseMenu.Item
        ref={ref}
        disabled={disabled}
        className={`flex w-full items-center gap-2 px-2.5 py-1.5 rounded-md text-xs font-medium cursor-pointer select-none transition-colors focus-visible:outline-none disabled:opacity-40 disabled:cursor-not-allowed ${
          destructive
            ? 'text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 focus:bg-rose-50 dark:focus:bg-rose-950/40'
            : 'text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/80 focus:bg-stone-100 dark:focus:bg-stone-800/80'
        } ${className}`}
        {...props}
      >
        {children}
      </BaseMenu.Item>
    );
  }
);

export function DropdownMenuSeparator({ className = '', ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={`my-1 h-px bg-stone-100 dark:bg-stone-800 ${className}`} {...props} />;
}
