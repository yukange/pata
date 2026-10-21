import React, { useState } from 'react';
import { AlertCircle, AlertTriangle, Info } from 'lucide-react';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogDescription } from './dialog';
import { Button } from './button';

export type ConfirmVariant = 'destructive' | 'warning' | 'default';

export interface ConfirmDialogProps {
  open: boolean;
  onOpenChange?: (open: boolean) => void;
  title: React.ReactNode;
  description: React.ReactNode;
  confirmText?: string;
  cancelText?: string;
  variant?: ConfirmVariant;
  preventDismissOnOutsideClick?: boolean;
  onConfirm: () => void | Promise<void>;
  onCancel: () => void;
}

export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmText = '确认',
  cancelText = '取消',
  variant = 'default',
  preventDismissOnOutsideClick = true,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  const [loading, setLoading] = useState(false);

  const handleConfirm = async () => {
    try {
      setLoading(true);
      await onConfirm();
    } catch (err) {
      console.error('ConfirmDialog action failed:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleOpenChange = (newOpen: boolean) => {
    if (loading) return;
    if (!newOpen) {
      onCancel();
    }
    onOpenChange?.(newOpen);
  };

  const iconMap = {
    destructive: (
      <div className="p-2 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 shrink-0">
        <AlertCircle className="w-5 h-5" />
      </div>
    ),
    warning: (
      <div className="p-2 rounded-full bg-amber-100 dark:bg-amber-950/60 text-amber-600 dark:text-amber-400 shrink-0">
        <AlertTriangle className="w-5 h-5" />
      </div>
    ),
    default: (
      <div className="p-2 rounded-full bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300 shrink-0">
        <Info className="w-5 h-5" />
      </div>
    ),
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange} disablePointerDismissal={preventDismissOnOutsideClick}>
      <DialogContent maxWidth="sm">
        <div className="flex items-start space-x-3">
          {iconMap[variant]}
          <DialogHeader className="flex-1">
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{description}</DialogDescription>
          </DialogHeader>
        </div>
        <DialogFooter>
          <Button variant="ghost" size="sm" onClick={onCancel} disabled={loading}>
            {cancelText}
          </Button>
          <Button
            variant={variant}
            size="sm"
            onClick={handleConfirm}
            loading={loading}
          >
            {confirmText}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
