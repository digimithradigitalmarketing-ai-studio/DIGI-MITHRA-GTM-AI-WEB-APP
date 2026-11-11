import { Notice } from "@/components/ui";

// Marks a screen whose figures are placeholders. Shown above the page header so no mock number
// can be read as a live business result. Remove it only when the screen reads real data.
export function DemoBanner({ detail }: { detail?: string }) {
  return (
    <div className="mb-6">
      <Notice tone="warning">
        <span className="font-semibold">Demo data.</span>{" "}
        {detail ?? "The figures on this screen are placeholders, not your live business results."}
      </Notice>
    </div>
  );
}
