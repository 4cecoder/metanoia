export function Prose({ children }: { children: React.ReactNode }) {
  return <div className="prose prose-neutral dark:prose-invert max-w-none">{children}</div>;
}
