# cmgOCR

cmgOCR is a small and simple app that performs OCR (Optical Character Recognition) on PDFs (single or multipage) or images (PNG, JPG, TIFF and BMP).

Once the OCR is performed, the user can edit the text (presented side by side with the orginal file) in markdown to add some basic formatting (headers, bold, italic…) and save the converted file either in Markdown or in RTF.

## What is cmgOCR and why did I create it

For years, all OCR application for macOS I used or tried have been expensive or cumbersome (in many cases both). My experience with them has not improved a lot since the times of Apple OneScanner (yep, in the ’90s): I would rather say it deteriorated. Yes, now you can take a photo with your iPhone and grab the text almost instantly, but this is not what I need for even slightly more demanding needs (I work a lot with long formatted texts).

My requirements for an OCR app are simple:

- Paragraphs must stay together
- I must be able to perform some editing to the text in order to add the original formatting (just the basics: headers, bold, italic). It's ok for me to do this by hand, but having some basic buttons or keyboard shortcuts is the difference between an excruciating process and a fast sequence of clicks and shortcuts. The time saved is of one order of magnitude, at least for me.

For some reason, I never managed to find anything that met these requirements.

## How I did it

I might have spent a year improving my very, very basic understanding of Swift and slightly – but not much – better understanding of generic coding and write myself the app I wanted. Or – as I did – vibe code wildly with Gemini.

This app will not win the "Best designed app of the Century" but it's compact and clean enough to do no harm and to do exactly what I need.

## What's under the hood

cmgOCR uses Apple's own Vision framework which performs surprisingly well and is native.

To keep things as simple as possible it's been intentionally developed for one platform only (macOS) and for its latest version available at the time when I started working on it which is 26.x.

## Few things that could be better...

...but probably won't because I don't have much time or interest in creating a perfect product:

- Lack of multi-column support.
- Languages supported for OCR are – for now – just English and Italian
- Some buttons are redundant and I don't particularly like their placement or design.
- When Markdown is chosen for the destination file, it is actually saved with a .txt extension. There's also an "Other format" option that doesn't make any sense (it's just the same file with no extension).
- The icon is what it is. I've seen worse.

## Disclaimer

You can clone this repository and build your own version of the app or download the ready-made release which is **unsigned**. It's up to you to override the Gatekeeper quarantine either via Terminal or through the more convenient [Sentinel](https://github.com/alienator88/Sentinel).

I hardly know what *I* am doing so I take no responsibility whatsoever for any use of this app. You've been warned.
