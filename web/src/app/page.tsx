import SiteNav from '@/components/SiteNav'
import Hero from '@/components/Hero'
import TheGap from '@/components/TheGap'
import Pipeline from '@/components/Pipeline'
import ScrollScene from '@/components/ScrollScene'
import DiagnosisGrid from '@/components/DiagnosisGrid'
import TakeTest from '@/components/TakeTest'
import AttentionModel from '@/components/AttentionModel'
import ExamTargets from '@/components/ExamTargets'
import CallToAction from '@/components/CallToAction'
import SiteFooter from '@/components/SiteFooter'
import Reveal from '@/components/Reveal'

export default function Home() {
  return (
    <>
      <SiteNav />
      <main>
        <Hero />
        <Reveal><TheGap /></Reveal>
        <Reveal><Pipeline /></Reveal>
        <ScrollScene />
        <Reveal><DiagnosisGrid /></Reveal>
        <TakeTest />
        <Reveal><AttentionModel /></Reveal>
        <Reveal><ExamTargets /></Reveal>
        <CallToAction />
      </main>
      <SiteFooter />
    </>
  )
}