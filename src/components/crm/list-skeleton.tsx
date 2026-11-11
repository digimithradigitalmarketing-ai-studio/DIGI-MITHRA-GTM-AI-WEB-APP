import { SkeletonBlock } from "@/components/ui";

export function ListSkeleton({ label }: { label: string }) {
  return (
    <div className="space-y-4" aria-busy="true" aria-label={`Loading ${label}`}>
      <SkeletonBlock className="h-10 w-64" />
      <SkeletonBlock className="h-16" />
      <SkeletonBlock className="h-80" />
    </div>
  );
}
