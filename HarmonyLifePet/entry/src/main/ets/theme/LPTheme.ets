export class LPColor {
  static readonly ink: string = '#1A1A1A';
  static readonly ink2: string = '#3A3A3A';
  static readonly muted: string = '#6E665A';
  static readonly faint: string = '#BBBBBB';
  static readonly hairline: string = '#E7E3D9';

  static readonly paper: string = '#FAF7EF';
  static readonly paperCool: string = '#FAFAF5';
  static readonly paperCard: string = '#FFFEF9';
  static readonly paperWarm: string = '#F4F0E4';
  static readonly kraft: string = '#E7E3D9';

  static readonly coral: string = '#D14B3D';
  static readonly coralSoft: string = '#FDF3F1';
  static readonly sage: string = '#3E7A5F';
  static readonly sageSoft: string = '#F0F6F2';

  static readonly sticky: string = '#FEF4A8';
  static readonly stickyInk: string = '#5A4A2A';

  // The LCD stage keeps the iOS PetStageView one-off tone rather than adding it
  // to the shared SwiftUI LP.Colors palette.
  static readonly lcd: string = '#EBE3CC';
  static readonly lcdDash: string = '#BFB89F';
  static readonly lcdInk: string = '#7D7657';
}

export class LPSpacing {
  static readonly s1: number = 4;
  static readonly s2: number = 8;
  static readonly s3: number = 12;
  static readonly s4: number = 16;
  static readonly s5: number = 24;
  static readonly s6: number = 32;
  static readonly s7: number = 48;
  static readonly s8: number = 64;

  static readonly inlineGap: number = LPSpacing.s1;
  static readonly fieldGap: number = LPSpacing.s2;
  static readonly tight: number = LPSpacing.s3;
  static readonly cardPadding: number = LPSpacing.s4;
  static readonly blockGap: number = LPSpacing.s5;
  static readonly sectionGap: number = LPSpacing.s7;
  static readonly screenMargin: number = LPSpacing.s5;
}

export class LPRadius {
  static readonly sharp: number = 0;
  static readonly button: number = 2;
  static readonly card: number = 4;
  static readonly input: number = 8;
  static readonly panel: number = 14;
  static readonly pill: number = 999;
}

export class LPBorder {
  static readonly regular: number = 1.5;
  static readonly hair: number = 1;
  static readonly heavy: number = 2;
  static readonly draftDash: number[] = [6, 4];
}

export class LPShadow {
  static readonly smRadius: number = 3;
  static readonly smOffsetY: number = 2;
  static readonly mdRadius: number = 6;
  static readonly mdOffsetY: number = 4;
  static readonly lgRadius: number = 12;
  static readonly lgOffsetY: number = 8;
}

export class LPSize {
  static readonly radiusSm: number = LPRadius.input;
  static readonly radiusMd: number = LPRadius.panel;
  static readonly radiusLg: number = 18;
  static readonly pagePadding: number = LPSpacing.screenMargin;
}

export class LPText {
  static readonly mono: string = 'monospace';
  static readonly rounded: string = 'sans-serif';
}
