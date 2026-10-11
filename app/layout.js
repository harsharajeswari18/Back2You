export const metadata = { title: 'Back2You' };
export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 820, margin: '2rem auto', padding: '0 1rem' }}>
        {children}
      </body>
    </html>
  );
}
