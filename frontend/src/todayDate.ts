// Today 页面只使用本地日历日期，避免 ISO UTC 日期在时区边界出错。
export function getLocalDateStr(d: Date = new Date()): string {
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// 仅在用户原本浏览「今天」时跨日跟随；主动浏览历史/未来日期不跳转。
export function followTodayOnDateChange(selectedDate: string, previousToday: string, nextToday: string): string {
  return selectedDate === previousToday ? nextToday : selectedDate;
}
