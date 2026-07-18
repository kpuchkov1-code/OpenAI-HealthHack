//
//  Consult.swift
//  AmberAI
//
//  The week-4 Dr Patel consultation. Ingesting it lands 7 clinical facts tagged
//  `consult`. Ported from lib/consult.ts.
//

import Foundation

struct ConsultLine: Identifiable, Hashable {
    let id = UUID()
    let speaker: String   // "Dr Patel" | "Kirill"
    let text: String
}

let CONSULT_TRANSCRIPT: [ConsultLine] = [
    ConsultLine(speaker: "Dr Patel", text: "Kirill, hiya. Can you hear me alright? Good. Right, so we're four weeks in on the 2.5. How are you getting on with it, honestly?"),
    ConsultLine(speaker: "Kirill", text: "Honestly? Bit of a mixed bag. The first fortnight was actually fine, better than fine really, and then the sickness turned up."),
    ConsultLine(speaker: "Dr Patel", text: "Okay. Tell me about the sickness. Is it constant, or is there a pattern to it?"),
    ConsultLine(speaker: "Kirill", text: "There's definitely a pattern. I jab on the Sunday, and Monday's fine, Tuesday's fine, and then Wednesday it just... hits. Day three, every single time. Usually late afternoon at my desk, which is a joy."),
    ConsultLine(speaker: "Dr Patel", text: "That's very typical, actually. Day three is when you're at peak levels. Are you actually being sick, or is it more queasiness?"),
    ConsultLine(speaker: "Kirill", text: "Queasy. I've not been sick. Reflux in the evenings, and I've gone completely off chicken, which is inconvenient because that was basically my whole diet."),
    ConsultLine(speaker: "Dr Patel", text: "Ha, yes, that one comes up a lot. Any abdominal pain? Anything sharp, or pain that goes through to your back?"),
    ConsultLine(speaker: "Kirill", text: "No, nothing like that. Just the queasiness."),
    ConsultLine(speaker: "Dr Patel", text: "Good. Now, I do want to flag that specifically, because it matters. If you ever get severe abdominal pain, particularly upper abdomen and particularly if it radiates round to your back, I want you to contact us urgently. Or A and E out of hours. That can point to your gallbladder or your pancreas and it's not something to sit on over a weekend. Rare, but I'd rather you knew."),
    ConsultLine(speaker: "Kirill", text: "Right. Okay. Noted."),
    ConsultLine(speaker: "Dr Patel", text: "It's not me trying to scare you, it's just the one thing I'd never want you to wait on. Everything else, ring us in the morning, that's fine. So. Weight's coming down steadily, side effects are unpleasant but they're within what I'd expect. I'd like to step you up to 5 milligrams."),
    ConsultLine(speaker: "Kirill", text: "Even with the nausea? I sort of assumed you'd say stay put."),
    ConsultLine(speaker: "Dr Patel", text: "I understand why, but 2.5 is really just a starter dose, it's there to let your gut get used to the drug. 5 is where we'd expect to see the actual benefit. And your day three pattern tells me your body is handling it, it's just grumbling about it. A couple of things that will help. First, try taking the jab at night rather than the evening, just before bed. Most people find they sleep through the worst of the peak."),
    ConsultLine(speaker: "Kirill", text: "That's such a simple thing. Right, I'll move it to Sunday night."),
    ConsultLine(speaker: "Dr Patel", text: "Second, and this is the one I'd really push on, protein. I want you aiming for about 100 grams a day. When you're losing weight this quickly there's a real risk you lose muscle along with the fat, and that's genuinely hard to get back. So protein at every meal even when you don't fancy it. And I'd add some resistance work if you can, a couple of sessions a week, nothing heroic."),
    ConsultLine(speaker: "Kirill", text: "100 grams sounds like a lot when I can barely finish a bowl of soup. And I've gone off chicken, so."),
    ConsultLine(speaker: "Dr Patel", text: "Greek yoghurt, eggs, fish, a shake if you're struggling. It doesn't have to be a chicken breast the size of your head. And hydration, please, drink more than you think you need. A lot of what people call Mounjaro fatigue is just plain dehydration, and it'll help the constipation too."),
    ConsultLine(speaker: "Kirill", text: "I'll try. It's just, my sister's getting married in September and I'm the best man, and I keep doing the maths in my head about whether any of this is going to be worth anything by then."),
    ConsultLine(speaker: "Dr Patel", text: "September's five months off, Kirill. That's plenty of time on 5, and possibly higher. But do me a favour and stop doing the maths, it never helps anyone. Keep talking to Amber between now and then, it's genuinely useful for me to see the pattern. I'll get the 5 milligram pens sent out today, and I'll see you in four weeks."),
    ConsultLine(speaker: "Kirill", text: "Thanks, Dr Patel. Really. That's helped."),
]

let CONSULT_FACTS: [MemoryFact] = [
    MemoryFact(id: "c-001", type: .medication, content: "Dr Patel stepped him up from 2.5mg to 5mg at the week 4 consult", source: .consult, weekLearned: 4, salience: 0.95),
    MemoryFact(id: "c-002", type: .clinicalInstruction, content: "Dr Patel advised taking the jab at night, just before bed, so he sleeps through the worst of the nausea", source: .consult, weekLearned: 4, salience: 0.9),
    MemoryFact(id: "c-003", type: .clinicalInstruction, content: "Dr Patel asked him to aim for roughly 100g of protein a day to protect muscle during rapid weight loss", source: .consult, weekLearned: 4, salience: 0.9),
    MemoryFact(id: "c-004", type: .clinicalInstruction, content: "Dr Patel told him to drink more than he thinks he needs, as fatigue and constipation are often dehydration", source: .consult, weekLearned: 4, salience: 0.8),
    MemoryFact(id: "c-005", type: .clinicalInstruction, content: "RED FLAG from Dr Patel: severe abdominal pain, especially upper abdomen radiating to the back, means contact the clinic urgently or go to A and E. Possible gallbladder or pancreatitis.", source: .consult, weekLearned: 4, salience: 0.95),
    MemoryFact(id: "c-006", type: .clinicalInstruction, content: "Dr Patel suggested two resistance sessions a week alongside the protein to preserve muscle", source: .consult, weekLearned: 4, salience: 0.75),
    MemoryFact(id: "c-007", type: .personal, content: "Told Dr Patel he is best man at his sister's September wedding and keeps doing the maths on timelines", source: .consult, weekLearned: 4, salience: 0.85),
]
