import React from 'react';
import { Dialog as BaseDialog } from '@base-ui/react/dialog';
import { X } from 'lucide-react';

export interface DialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  children: React.ReactNode;
  disablePointerDismissal?: boolean;
}

export function Dialog({ open, onOpenChange, children, disablePointerDismissal = false }: DialogProps) {
  return (
    <BaseDialog.Root open={open} onOpenChange={onOpenChange} disablePointerDismissal={disablePointerDismissal}>
      {children}
    </BaseDialog.Root>
  );
}

export interface DialogContentProps extends React.HTMLAttributes<HTMLDivElement> {
  showCloseButton?: boolean;
  maxWidth?: 'sm' | 'md' | 'lg' | 'xl';
  padded?: boolean;
}

const maxWidthMap = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-xl',
};

export const DialogContent = React.forwardRef<HTMLDivElement, DialogContentProps>(function DialogContent(
  { children, className = '', showCloseButton = false, maxWidth = 'md', padded = true, ...props },
  ref
) {
  return (
    <BaseDialog.Portal>
      <BaseDialog.Backdrop className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-4 pata-fade" />
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none">
        <BaseDialog.Popup
          ref={ref}
          className={`pointer-events-auto relative w-full ${maxWidthMap[maxWidth]} rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 ${
            padded ? 'p-5 space-y-4' : ''
          } shadow-2xl pata-pop focus:outline-none ${className}`}
          {...props}
        >
          {showCloseButton && (
            <BaseDialog.Close
              className="absolute top-4 right-4 p-1 rounded-md text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)] cursor-pointer"
              aria-label="关闭"
            >
              <X className="w-4 h-4" />
            </BaseDialog.Close>
          )}
          {children}
        </BaseDialog.Popup>
      </div>
    </BaseDialog.Portal>
  );
});

export function DialogHeader({ className = '', children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={`space-y-1 ${className}`} {...props}>
      {children}
    </div>
  );
}

export function DialogTitle({ className = '', children, ...props }: React.HTMLAttributes<HTMLHeadingElement>) {
  return (
    <BaseDialog.Title className={`text-sm font-semibold text-stone-900 dark:text-stone-100 ${className}`} {...props}>
      {children}
    </BaseDialog.Title>
  );
}

export function DialogDescription({ className = '', children, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return (
    <BaseDialog.Description className={`text-xs text-stone-500 dark:text-stone-400 leading-relaxed ${className}`} {...props}>
      {children}
    </BaseDialog.Description>
  );
}

export function DialogFooter({ className = '', children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={`flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800/80 ${className}`}
      {...props}
    >
      {children}
    </div>
  );
}

export const DialogTrigger = BaseDialog.Trigger;
export const DialogClose = BaseDialog.Close;
