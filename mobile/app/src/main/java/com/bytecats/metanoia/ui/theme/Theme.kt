package com.bytecats.metanoia.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.googlefonts.Font
import androidx.compose.ui.text.googlefonts.GoogleFont
import androidx.compose.ui.unit.sp
import com.bytecats.metanoia.R

val provider = GoogleFont.Provider(
    providerAuthority = "com.google.android.gms.fonts",
    providerPackage = "com.google.android.gms",
    certificates = R.array.com_google_android_gms_fonts_certs
)

val PlayfairFont = GoogleFont("Playfair Display")
val InterFont = GoogleFont("Inter")

val PlayfairFamily = FontFamily(
    Font(googleFont = PlayfairFont, fontProvider = provider),
    Font(googleFont = PlayfairFont, fontProvider = provider, weight = FontWeight.Bold),
    Font(googleFont = PlayfairFont, fontProvider = provider, weight = FontWeight.Black)
)

val InterFamily = FontFamily(
    Font(googleFont = InterFont, fontProvider = provider),
    Font(googleFont = InterFont, fontProvider = provider, weight = FontWeight.Medium),
    Font(googleFont = InterFont, fontProvider = provider, weight = FontWeight.SemiBold)
)

val MetanoiaTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = PlayfairFamily,
        fontWeight = FontWeight.Black,
        fontSize = 32.sp,
        letterSpacing = (-1).sp
    ),
    headlineMedium = TextStyle(
        fontFamily = PlayfairFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 24.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp
    ),
    labelSmall = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp
    )
)

@Composable
fun MetanoiaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFF7aa2f7),
            surface = Color(0xFF1a1b26),
            surfaceVariant = Color(0xFF24283b),
            onSurface = Color(0xFFcfc9c2),
            outline = Color(0xFF414868)
        ),
        typography = MetanoiaTypography,
        content = content
    )
}
