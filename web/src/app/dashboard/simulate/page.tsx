import PageHead from '@/components/dashboard/PageHead'
import Simulator from '@/components/dashboard/Simulator'

export default function SimulatePage() {
  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="SIMULATE"
        title="Spend the hours before you spend them."
        lede="Move hours between subjects and watch the projected score move. The model runs forward through your mastery estimates and forgetting curves, so the answer is not linear."
      />
      <Simulator />
    </main>
  )
}